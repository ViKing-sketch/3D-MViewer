cmake_minimum_required(VERSION 3.21)
project(field_bim_viewer VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(FBV_BUILD_TESTS "Build unit tests" ON)
option(FBV_WITH_OCCT "Link Open CASCADE 7.8.1 (not used by the analytic MVP)" OFF)
option(FBV_WITH_IFCOPENSHELL "Link IfcOpenShell (not used by the analytic MVP)" OFF)

if(FBV_BUILD_TESTS)
  enable_testing()
endif()

if(FBV_WITH_OCCT OR FBV_WITH_IFCOPENSHELL)
  message(FATAL_ERROR
    "FBV_WITH_OCCT and FBV_WITH_IFCOPENSHELL are reserved for the OCCT/IfcOpenShell superbuild. "
    "The host MVP converter does not link them yet. See deps/CMakeLists.txt.")
endif()

function(fbv_warnings target)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /utf-8 /permissive-)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endif()
endfunction()

# Windows loads fbv_core.dll from the directory of the executable.
function(fbv_copy_core_dll target)
  if(WIN32)
    add_custom_command(
      TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:fbv_core>
              $<TARGET_FILE_DIR:${target}>
      VERBATIM)
  endif()
endfunction()

add_subdirectory(third_party/sqlite)
add_subdirectory(deps)
add_subdirectory(core)
add_subdirectory(converter)
