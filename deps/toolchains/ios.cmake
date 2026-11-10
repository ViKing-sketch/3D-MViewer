if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR
    "The ios preset targets a future xcframework build (task Z20). "
    "Configure it on macOS with -DCMAKE_SYSTEM_NAME=iOS and a selected sysroot. "
    "It is not part of the host MVP.")
endif()
