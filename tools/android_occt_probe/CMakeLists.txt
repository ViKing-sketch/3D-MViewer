cmake_minimum_required(VERSION 3.16)
project(fbv_android_occt_probe LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCASCADE REQUIRED)

function(fbv_link_occt target)
  target_include_directories(${target} PRIVATE ${OpenCASCADE_INCLUDE_DIR} ${CMAKE_CURRENT_SOURCE_DIR})
  # Box, exact mass properties, and BinTools. TKDESTEP and XDE are not linked.
  target_link_libraries(${target} PRIVATE
    TKernel
    TKMath
    TKG2d
    TKG3d
    TKGeomBase
    TKBRep
    TKGeomAlgo
    TKTopAlgo
    TKPrim
  )
endfunction()

add_executable(occt_probe probe.cpp probe_run.cpp)
fbv_link_occt(occt_probe)

if(ANDROID)
  add_library(occt_probe_jni SHARED probe_jni.cpp probe_run.cpp)
  fbv_link_occt(occt_probe_jni)
endif()
