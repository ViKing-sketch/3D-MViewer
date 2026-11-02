# Android arm64 toolchain wrapper for preset android-arm64 (task Z03).
# The NDK build of OCCT is intentionally not part of the host MVP.

if(NOT ANDROID_NDK AND DEFINED ENV{ANDROID_NDK_HOME})
  set(ANDROID_NDK "$ENV{ANDROID_NDK_HOME}")
endif()
if(NOT ANDROID_NDK AND DEFINED ENV{ANDROID_NDK})
  set(ANDROID_NDK "$ENV{ANDROID_NDK}")
endif()

if(NOT ANDROID_NDK OR NOT EXISTS "${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
  message(FATAL_ERROR
    "Android NDK not found. Set ANDROID_NDK_HOME to an NDK that contains "
    "build/cmake/android.toolchain.cmake. OCCT for Android is task Z03 and is not "
    "built by the Linux/Windows host presets.")
endif()

set(ANDROID_ABI arm64-v8a CACHE STRING "")
set(ANDROID_PLATFORM android-26 CACHE STRING "")
include("${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
