cmake_minimum_required(VERSION 3.16)
project(fbv_android_occt_probe LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenCASCADE REQUIRED)

add_executable(occt_probe probe.cpp)
target_include_directories(occt_probe PRIVATE ${OpenCASCADE_INCLUDE_DIR})
# Box, exact mass properties, and BinTools. TKDESTEP and XDE are not linked.
target_link_libraries(occt_probe PRIVATE
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
