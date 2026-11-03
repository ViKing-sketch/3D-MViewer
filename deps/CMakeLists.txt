# SQLite is vendored. IfcOpenShell (v0.8.5, OCCT kernel) and Open CASCADE 7.8.1
# are fetched and built when FBV_WITH_IFCOPENSHELL=ON.
#
# Open CASCADE is configured in its own CMake process: its lists use
# CMAKE_SOURCE_DIR, so it cannot be add_subdirectory'd into this project.
# The first configure compiles and installs it under the build tree and reuses
# that install afterwards. IfcOpenShell is then added as a subdirectory against
# that install. Schemas are the ones shipped in the IfcOpenShell tree
# (IFC2X3, IFC4, IFC4X3_ADD2); Python is not required.

add_library(fbv_deps INTERFACE)
add_dependencies(fbv_deps sqlite3_amalgamation)

if(NOT FBV_WITH_IFCOPENSHELL)
  return()
endif()

if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

include(FetchContent)
include(ProcessorCount)

set(FBV_IOS_GIT_SHA "481676e51b65cb93e520b9f073123f22a06b212b")
set(FBV_OCCT_PREFIX "${CMAKE_BINARY_DIR}/occt-install")
set(FBV_OCCT_STAMP "${FBV_OCCT_PREFIX}/.fbv-occt-7.8.1")

FetchContent_Declare(occt781
  URL https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_8_1.tar.gz
)
FetchContent_GetProperties(occt781)
if(NOT occt781_POPULATED)
  FetchContent_Populate(occt781)
endif()

if(NOT EXISTS "${FBV_OCCT_STAMP}")
  if(FBV_SUPERBUILD_JOBS STREQUAL "")
    ProcessorCount(FBV_OCCT_JOBS)
    if(FBV_OCCT_JOBS EQUAL 0)
      set(FBV_OCCT_JOBS 2)
    endif()
  else()
    set(FBV_OCCT_JOBS "${FBV_SUPERBUILD_JOBS}")
  endif()

  set(FBV_OCCT_BUILD "${CMAKE_BINARY_DIR}/occt-build")
  file(MAKE_DIRECTORY "${FBV_OCCT_BUILD}")
  message(STATUS "Configuring Open CASCADE 7.8.1 into ${FBV_OCCT_BUILD} (${FBV_OCCT_JOBS} jobs)")

  set(OCCT_ARGS
    -G "${CMAKE_GENERATOR}"
    -S "${occt781_SOURCE_DIR}"
    -B "${FBV_OCCT_BUILD}"
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_INSTALL_PREFIX=${FBV_OCCT_PREFIX}
    -DBUILD_LIBRARY_TYPE=Shared
    -DINSTALL_DIR_LAYOUT=Unix
    -DINSTALL_DIR_WITH_VERSION=OFF
    -DBUILD_MODULE_Draw=OFF
    -DBUILD_MODULE_Visualization=OFF
    -DBUILD_MODULE_DETools=OFF
    -DBUILD_MODULE_FoundationClasses=ON
    -DBUILD_MODULE_ModelingData=ON
    -DBUILD_MODULE_ModelingAlgorithms=ON
    -DBUILD_MODULE_ApplicationFramework=ON
    -DBUILD_MODULE_DataExchange=ON
    -DBUILD_DOC_Overview=OFF
    -DBUILD_Inspector=OFF
    -DBUILD_SAMPLES_QT=OFF
    -DBUILD_RELEASE_DISABLE_EXCEPTIONS=OFF
    -DUSE_FREETYPE=OFF
    -DUSE_TK=OFF
    -DUSE_FREEIMAGE=OFF
    -DUSE_FFMPEG=OFF
    -DUSE_TBB=OFF
    -DUSE_RAPIDJSON=OFF
    -DUSE_DRACO=OFF
    -DUSE_EIGEN=OFF
    -DUSE_OPENGL=OFF
    -DUSE_GLES2=OFF
    -DUSE_XLIB=OFF
    -DUSE_D3D=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  )
  if(CMAKE_GENERATOR_PLATFORM)
    list(APPEND OCCT_ARGS -A "${CMAKE_GENERATOR_PLATFORM}")
  endif()
  if(CMAKE_GENERATOR_TOOLSET)
    list(APPEND OCCT_ARGS -T "${CMAKE_GENERATOR_TOOLSET}")
  endif()
  if(NOT CMAKE_CONFIGURATION_TYPES)
    list(APPEND OCCT_ARGS -DCMAKE_BUILD_TYPE=Release)
    if(CMAKE_C_COMPILER)
      list(APPEND OCCT_ARGS -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER})
    endif()
    if(CMAKE_CXX_COMPILER)
      list(APPEND OCCT_ARGS -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER})
    endif()
  endif()

  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${OCCT_ARGS}
    RESULT_VARIABLE FBV_OCCT_CFG
    OUTPUT_FILE "${FBV_OCCT_BUILD}/configure.log"
    ERROR_FILE "${FBV_OCCT_BUILD}/configure.log"
  )
  if(NOT FBV_OCCT_CFG EQUAL 0)
    message(FATAL_ERROR
      "Open CASCADE 7.8.1 configure failed (exit ${FBV_OCCT_CFG}). See ${FBV_OCCT_BUILD}/configure.log")
  endif()

  set(OCCT_BUILD_ARGS --build "${FBV_OCCT_BUILD}" --parallel "${FBV_OCCT_JOBS}")
  if(CMAKE_CONFIGURATION_TYPES)
    list(APPEND OCCT_BUILD_ARGS --config Release)
  endif()
  message(STATUS "Building Open CASCADE 7.8.1. The first configure is the long step; later configures reuse ${FBV_OCCT_PREFIX}.")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${OCCT_BUILD_ARGS}
    RESULT_VARIABLE FBV_OCCT_BLD
    OUTPUT_FILE "${FBV_OCCT_BUILD}/build.log"
    ERROR_FILE "${FBV_OCCT_BUILD}/build.log"
  )
  if(NOT FBV_OCCT_BLD EQUAL 0)
    message(FATAL_ERROR
      "Open CASCADE 7.8.1 build failed (exit ${FBV_OCCT_BLD}). See ${FBV_OCCT_BUILD}/build.log")
  endif()

  set(OCCT_INSTALL_ARGS --install "${FBV_OCCT_BUILD}")
  if(CMAKE_CONFIGURATION_TYPES)
    list(APPEND OCCT_INSTALL_ARGS --config Release)
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" ${OCCT_INSTALL_ARGS}
    RESULT_VARIABLE FBV_OCCT_INS
    OUTPUT_FILE "${FBV_OCCT_BUILD}/install.log"
    ERROR_FILE "${FBV_OCCT_BUILD}/install.log"
  )
  if(NOT FBV_OCCT_INS EQUAL 0)
    message(FATAL_ERROR
      "Open CASCADE 7.8.1 install failed (exit ${FBV_OCCT_INS}). See ${FBV_OCCT_BUILD}/install.log")
  endif()
  file(WRITE "${FBV_OCCT_STAMP}" "occt 7.8.1\n")
else()
  message(STATUS "Reusing Open CASCADE 7.8.1 at ${FBV_OCCT_PREFIX}")
endif()

set(FBV_OCCT_LIB_DIR "${FBV_OCCT_PREFIX}/lib")
set(FBV_OCCT_BIN_DIR "${FBV_OCCT_PREFIX}/bin")
set(FBV_OCCT_INCLUDE_DIR "${FBV_OCCT_PREFIX}/include/opencascade")
set(OpenCASCADE_DIR "${FBV_OCCT_PREFIX}/lib/cmake/opencascade" CACHE PATH "Installed OCCT 7.8.1" FORCE)
if(NOT EXISTS "${OpenCASCADE_DIR}/OpenCASCADEConfig.cmake")
  message(FATAL_ERROR "Open CASCADE config was not installed at ${OpenCASCADE_DIR}")
endif()

# IfcOpenShell forces static Boost on Windows unless this is set. Dynamic Boost
# (vcpkg x64-windows, or a shared system package) matches the MSVC release CRT.
if(WIN32)
  set(ENV{CONDA_BUILD} "1")
endif()

# Header-only pieces IfcOpenShell includes (logic, uuid, scope_exit, optional, ...)
# are not Boost COMPONENTS. On vcpkg they are separate ports listed in vcpkg.json.
# locale is compiled; IfcCharacterDecoder calls boost::locale::conv::utf_to_utf.
find_package(Boost REQUIRED COMPONENTS system program_options regex thread date_time iostreams locale)
if(NOT Boost_LIBRARIES)
  set(Boost_LIBRARIES
    Boost::system
    Boost::program_options
    Boost::regex
    Boost::thread
    Boost::date_time
    Boost::iostreams
    Boost::locale
  )
endif()
if(NOT Boost_INCLUDE_DIRS)
  if(TARGET Boost::boost)
    get_target_property(Boost_INCLUDE_DIRS Boost::boost INTERFACE_INCLUDE_DIRECTORIES)
  elseif(DEFINED Boost_INCLUDE_DIR)
    set(Boost_INCLUDE_DIRS "${Boost_INCLUDE_DIR}")
  endif()
endif()

set(MINIMAL_BUILD ON CACHE BOOL "" FORCE)
set(BUILD_IFCGEOM ON CACHE BOOL "" FORCE)
set(BUILD_IFCPYTHON OFF CACHE BOOL "" FORCE)
set(BUILD_CONVERT OFF CACHE BOOL "" FORCE)
set(BUILD_GEOMSERVER OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_IFCMAX OFF CACHE BOOL "" FORCE)
set(BUILD_QTVIEWER OFF CACHE BOOL "" FORCE)
set(BUILD_DOCUMENTATION OFF CACHE BOOL "" FORCE)
set(BUILD_PACKAGE OFF CACHE BOOL "" FORCE)
set(WITH_OPENCASCADE ON CACHE BOOL "" FORCE)
set(WITH_CGAL OFF CACHE BOOL "" FORCE)
set(COLLADA_SUPPORT OFF CACHE BOOL "" FORCE)
set(GLTF_SUPPORT OFF CACHE BOOL "" FORCE)
set(HDF5_SUPPORT OFF CACHE BOOL "" FORCE)
set(IFCXML_SUPPORT OFF CACHE BOOL "" FORCE)
set(USD_SUPPORT OFF CACHE BOOL "" FORCE)
set(WITH_PROJ OFF CACHE BOOL "" FORCE)
set(WITH_ROCKSDB OFF CACHE BOOL "" FORCE)
set(WITH_ZSTD OFF CACHE BOOL "" FORCE)
set(USE_MMAP OFF CACHE BOOL "" FORCE)
set(ADD_COMMIT_SHA OFF CACHE BOOL "" FORCE)
set(VERSION_OVERRIDE ON CACHE BOOL "" FORCE)
set(NO_WARN ON CACHE BOOL "" FORCE)
set(SCHEMA_VERSIONS "2x3;4;4x3_add2" CACHE STRING "" FORCE)

set(_fbv_shared_libs "${BUILD_SHARED_LIBS}")
set(BUILD_SHARED_LIBS OFF)
FetchContent_Declare(ifcopenshell
  URL "https://github.com/IfcOpenShell/IfcOpenShell/archive/${FBV_IOS_GIT_SHA}.tar.gz"
)
FetchContent_GetProperties(ifcopenshell)
if(NOT ifcopenshell_POPULATED)
  FetchContent_Populate(ifcopenshell)
endif()

# Re-applied on a clean configure. The patch is idempotent: a tree that already
# contains it is left alone. git apply does not need a git checkout of IfcOpenShell.
set(FBV_IOS_PATCH "${CMAKE_CURRENT_SOURCE_DIR}/patches/ifcopenshell-msvc-memory.patch")
find_package(Git REQUIRED)
# The extracted tree sits inside this repo. Without a ceiling, git apply finds the
# parent .git and exits 0 without changing IfcOpenShell.
set(FBV_IOS_GIT_ENV "${CMAKE_COMMAND}" -E env "GIT_CEILING_DIRECTORIES=${CMAKE_SOURCE_DIR}")
execute_process(
  COMMAND ${FBV_IOS_GIT_ENV}
          "${GIT_EXECUTABLE}" apply --check --reverse --whitespace=nowarn "${FBV_IOS_PATCH}"
  WORKING_DIRECTORY "${ifcopenshell_SOURCE_DIR}"
  RESULT_VARIABLE FBV_IOS_ALREADY
  OUTPUT_QUIET ERROR_QUIET
)
if(NOT FBV_IOS_ALREADY EQUAL 0)
  execute_process(
    COMMAND ${FBV_IOS_GIT_ENV}
            "${GIT_EXECUTABLE}" apply --whitespace=nowarn "${FBV_IOS_PATCH}"
    WORKING_DIRECTORY "${ifcopenshell_SOURCE_DIR}"
    RESULT_VARIABLE FBV_IOS_APPLY
    ERROR_VARIABLE FBV_IOS_APPLY_ERR
  )
  if(NOT FBV_IOS_APPLY EQUAL 0)
    message(FATAL_ERROR
      "Failed to patch IfcOpenShell at ${ifcopenshell_SOURCE_DIR} (exit ${FBV_IOS_APPLY}): ${FBV_IOS_APPLY_ERR}")
  endif()
  message(STATUS "Patched IfcOpenShell for MSVC 19.50 profile init and bounded OCCT shape memory")
else()
  message(STATUS "IfcOpenShell patch already applied in ${ifcopenshell_SOURCE_DIR}")
endif()

add_subdirectory("${ifcopenshell_SOURCE_DIR}/cmake" "${ifcopenshell_BINARY_DIR}" EXCLUDE_FROM_ALL)
# IfcParse is linked with the plain signature inside IfcOpenShell. Mixing in
# PUBLIC/PRIVATE is a configure error.
if(TARGET Boost::locale)
  target_link_libraries(IfcParse Boost::locale)
endif()
set(BUILD_SHARED_LIBS "${_fbv_shared_libs}")

add_library(fbv_ifcopenshell INTERFACE)
target_link_libraries(fbv_ifcopenshell INTERFACE IfcGeom IfcParse)
target_include_directories(fbv_ifcopenshell SYSTEM INTERFACE
  "${ifcopenshell_SOURCE_DIR}/src"
  ${Boost_INCLUDE_DIRS}
  "${FBV_OCCT_INCLUDE_DIR}"
)
target_compile_definitions(fbv_ifcopenshell INTERFACE
  FBV_WITH_IFCOPENSHELL=1
  IFOPSH_WITH_OPENCASCADE=1
)
set(FBV_OCCT_LIB_DIR "${FBV_OCCT_LIB_DIR}" CACHE INTERNAL "")
set(FBV_OCCT_BIN_DIR "${FBV_OCCT_BIN_DIR}" CACHE INTERNAL "")
set(FBV_IFCOPENSHELL_SOURCE "${ifcopenshell_SOURCE_DIR}" CACHE INTERNAL "")

# Object files of the Open CASCADE kernel are not archived into IfcGeom.
# Consumers add $<TARGET_OBJECTS:geometry_kernel_opencascade>.
if(NOT TARGET geometry_kernel_opencascade)
  message(FATAL_ERROR "IfcOpenShell did not create geometry_kernel_opencascade")
endif()
