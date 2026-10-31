add_library(fbv_converter STATIC
  src/ifc_parse.cpp
  src/scene.cpp
  src/write_pkg.cpp
  src/validate.cpp
  src/convert.cpp
)
target_include_directories(fbv_converter PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(fbv_converter PUBLIC fbv_format fbv_core)
fbv_warnings(fbv_converter)

add_executable(fbvconv src/main.cpp)
target_link_libraries(fbvconv PRIVATE fbv_converter)
fbv_warnings(fbvconv)

add_executable(pkg_validate src/pkg_validate_main.cpp)
target_link_libraries(pkg_validate PRIVATE fbv_converter)
fbv_warnings(pkg_validate)

if(FBV_BUILD_TESTS)
  file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/testdata" FBV_TESTDATA_DIR)
  add_executable(converter_tests tests/converter_tests.cpp)
  target_link_libraries(converter_tests PRIVATE fbv_converter fbv_core)
  target_compile_definitions(converter_tests PRIVATE FBV_TESTDATA_DIR="${FBV_TESTDATA_DIR}")
  fbv_warnings(converter_tests)
  add_test(NAME converter_tests COMMAND converter_tests)
  set_tests_properties(converter_tests PROPERTIES
    ENVIRONMENT "FBV_FBVCONV=$<TARGET_FILE:fbvconv>;FBV_PKG_VALIDATE=$<TARGET_FILE:pkg_validate>"
  )
endif()
