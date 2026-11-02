add_library(fbv_converter STATIC
  src/ifc_parse.cpp
  src/scene.cpp
  src/ifc_geom_mesh.cpp
  src/write_pkg.cpp
  src/validate.cpp
  src/convert.cpp
)
target_include_directories(fbv_converter PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(fbv_converter PUBLIC fbv_format fbv_core)
if(WIN32)
  target_link_libraries(fbv_converter PUBLIC psapi)
endif()
if(FBV_WITH_IFCOPENSHELL)
  target_link_libraries(fbv_converter PUBLIC fbv_ifcopenshell)
  target_sources(fbv_converter PRIVATE $<TARGET_OBJECTS:geometry_kernel_opencascade>)
  target_compile_definitions(fbv_converter PUBLIC FBV_WITH_IFCOPENSHELL=1)
  if(UNIX AND FBV_OCCT_LIB_DIR)
    set_property(TARGET fbv_converter PROPERTY BUILD_RPATH "${FBV_OCCT_LIB_DIR}")
  endif()
endif()
fbv_warnings(fbv_converter)

add_executable(fbvconv src/main.cpp)
target_link_libraries(fbvconv PRIVATE fbv_converter)
fbv_warnings(fbvconv)
fbv_copy_core_dll(fbvconv)

add_executable(pkg_validate src/pkg_validate_main.cpp)
target_link_libraries(pkg_validate PRIVATE fbv_converter)
fbv_warnings(pkg_validate)
fbv_copy_core_dll(pkg_validate)

if(FBV_WITH_IFCOPENSHELL)
  foreach(tgt fbvconv pkg_validate)
    if(UNIX)
      set_property(TARGET ${tgt} APPEND PROPERTY BUILD_RPATH "${FBV_OCCT_LIB_DIR}")
      # DT_RPATH (not RUNPATH) is searched for transitive OCCT dependencies.
      target_link_options(${tgt} PRIVATE "-Wl,--disable-new-dtags")
    endif()
    if(WIN32)
      add_custom_command(
        TARGET ${tgt} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${FBV_OCCT_BIN_DIR}" "$<TARGET_FILE_DIR:${tgt}>"
        VERBATIM)
    endif()
  endforeach()
endif()

if(FBV_BUILD_TESTS)
  file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/testdata" FBV_TESTDATA_DIR)
  add_executable(converter_tests tests/converter_tests.cpp)
  target_link_libraries(converter_tests PRIVATE fbv_converter fbv_core)
  target_compile_definitions(converter_tests PRIVATE FBV_TESTDATA_DIR="${FBV_TESTDATA_DIR}")
  fbv_warnings(converter_tests)
  fbv_copy_core_dll(converter_tests)
  set(_fbv_test_env "FBV_FBVCONV=$<TARGET_FILE:fbvconv>;FBV_PKG_VALIDATE=$<TARGET_FILE:pkg_validate>")
  if(FBV_WITH_IFCOPENSHELL AND UNIX)
    set_property(TARGET converter_tests APPEND PROPERTY BUILD_RPATH "${FBV_OCCT_LIB_DIR}")
    target_link_options(converter_tests PRIVATE "-Wl,--disable-new-dtags")
    string(APPEND _fbv_test_env ";LD_LIBRARY_PATH=${FBV_OCCT_LIB_DIR}")
  endif()
  if(FBV_WITH_IFCOPENSHELL AND WIN32)
    add_custom_command(
      TARGET converter_tests POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_directory "${FBV_OCCT_BIN_DIR}" "$<TARGET_FILE_DIR:converter_tests>"
      VERBATIM)
    string(APPEND _fbv_test_env ";PATH=${FBV_OCCT_BIN_DIR};$ENV{PATH}")
  endif()
  add_test(NAME converter_tests COMMAND converter_tests)
  set_tests_properties(converter_tests PROPERTIES ENVIRONMENT "${_fbv_test_env}")
endif()
