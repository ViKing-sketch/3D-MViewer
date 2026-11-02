add_library(fbv_format STATIC
  src/io.cpp
  src/sha256.cpp
  src/json.cpp
  src/zip.cpp
  src/glb.cpp
  src/sqlite_util.cpp
)
target_include_directories(fbv_format PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(fbv_format PUBLIC sqlite3_amalgamation)
fbv_warnings(fbv_format)

add_library(fbv_core SHARED
  src/package.cpp
  src/c_api.cpp
)
target_include_directories(fbv_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(fbv_core PRIVATE fbv_format)
target_compile_definitions(fbv_core PRIVATE FBV_CORE_BUILD)
target_compile_definitions(fbv_core PUBLIC FBV_CORE_SHARED)
set_target_properties(fbv_core PROPERTIES
  OUTPUT_NAME fbv_core
  VERSION ${PROJECT_VERSION}
  SOVERSION 0
)
fbv_warnings(fbv_core)

if(FBV_BUILD_TESTS)
  add_executable(core_tests tests/core_tests.cpp)
  target_link_libraries(core_tests PRIVATE fbv_format fbv_core)
  fbv_warnings(core_tests)
  fbv_copy_core_dll(core_tests)
  add_test(NAME core_tests COMMAND core_tests)
endif()
