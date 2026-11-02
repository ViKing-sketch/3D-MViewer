# Host dependencies that the MVP links directly are vendored (SQLite amalgamation).
# OCCT 7.8.1, IfcOpenShell, meshoptimizer, zstd and Filament are opt-in superbuild
# steps. They are not configured by the default presets: a full OCCT build is a
# multi-hour download and is tasks Z02–Z07, not the host MVP.

add_library(fbv_deps INTERFACE)
add_dependencies(fbv_deps sqlite3_amalgamation)

option(FBV_SUPERBUILD_OCCT "Download and build Open CASCADE 7.8.1" OFF)
option(FBV_SUPERBUILD_IFCOPENSHELL "Download IfcOpenShell v0.8 against the superbuild OCCT" OFF)

if(FBV_SUPERBUILD_OCCT)
  include(ExternalProject)
  set(FBV_OCCT_PREFIX "${CMAKE_BINARY_DIR}/occt-install")
  ExternalProject_Add(occt781
    URL https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_8_1.tar.gz
    UPDATE_DISCONNECTED ON
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${FBV_OCCT_PREFIX}
      -DCMAKE_BUILD_TYPE=Release
      -DBUILD_LIBRARY_TYPE=Shared
      -DBUILD_MODULE_Draw=OFF
      -DBUILD_MODULE_Visualization=OFF
      -DBUILD_DOC_Overview=OFF
      -DUSE_FREETYPE=OFF
      -DUSE_TCL=OFF
      -DUSE_TK=OFF
      -DUSE_OPENGL=OFF
      -DUSE_GLES2=OFF
      -DINSTALL_DIR_LAYOUT=Unix
  )
  message(STATUS "OCCT 7.8.1 superbuild enabled. Flags are a starting point and were not executed in MVP CI.")
endif()

if(FBV_SUPERBUILD_IFCOPENSHELL)
  if(NOT FBV_SUPERBUILD_OCCT)
    message(FATAL_ERROR "FBV_SUPERBUILD_IFCOPENSHELL requires FBV_SUPERBUILD_OCCT")
  endif()
  include(ExternalProject)
  ExternalProject_Add(ifcopenshell
    URL https://github.com/IfcOpenShell/IfcOpenShell/archive/refs/tags/v0.8.2.tar.gz
    DEPENDS occt781
    UPDATE_DISCONNECTED ON
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=${CMAKE_BINARY_DIR}/ifcopenshell-install
      -DCMAKE_PREFIX_PATH=${FBV_OCCT_PREFIX}
      -DOCC_INCLUDE_DIR=${FBV_OCCT_PREFIX}/include/opencascade
      -DOCC_LIBRARY_DIR=${FBV_OCCT_PREFIX}/lib
      -DBUILD_IFCPYTHON=OFF
      -DBUILD_IFCGEOM=ON
      -DCOLLADA_SUPPORT=OFF
  )
  message(STATUS "IfcOpenShell superbuild enabled. Schema/OCCT flags may need adjustment for v0.8.2.")
endif()
