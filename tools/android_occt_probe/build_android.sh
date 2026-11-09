#!/usr/bin/env bash
# Cross-build Open CASCADE 7.8.1 for Android and link tools/android_occt_probe.
#
# This does not write a .fbvpkg and does not change format_version. The probe
# creates one temporary BinTools file and deletes it. A host build of the same
# source is not an Android result: the binary is run only with adb, and only
# when --run is passed and a device of the requested ABI is connected.
#
# Required: Android NDK 28.2.13676358 (the NDK the Flutter app already pins).
#   ANDROID_SDK_ROOT  default /tmp/android-sdk
#   ANDROID_NDK_HOME  default $ANDROID_SDK_ROOT/ndk/28.2.13676358
#
# Usage:
#   tools/android_occt_probe/build_android.sh --abi arm64-v8a
#   tools/android_occt_probe/build_android.sh --abi x86_64 --run
#
# OCCT is fetched from the 7.8.1 tag if missing. The tarball sha256 is checked.

set -euo pipefail

ABI="arm64-v8a"
PLATFORM="android-28"
RUN=0
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-/tmp/android-sdk}"
NDK="${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}"
CACHE="${FBV_OCCT_CACHE:-/tmp/occt-src}"
TARBALL="$CACHE/occt-V7_8_1.tar.gz"
SRC="$CACHE/OCCT-7_8_1"
SHA="7321af48c34dc253bf8aae3f0430e8cb10976961d534d8509e72516978aa82f5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --abi) ABI="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --run) RUN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$ABI" in
  arm64-v8a|x86_64) ;;
  *) echo "abi must be arm64-v8a or x86_64" >&2; exit 2 ;;
esac

if [[ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]]; then
  echo "NDK toolchain missing: $NDK" >&2
  exit 2
fi

mkdir -p "$CACHE"
if [[ ! -f "$TARBALL" ]]; then
  curl -fsSL -o "$TARBALL" https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/V7_8_1.tar.gz
fi
echo "$SHA  $TARBALL" | sha256sum -c -
if [[ ! -d "$SRC/src" ]]; then
  tar -xzf "$TARBALL" -C "$CACHE"
fi

# Platform is part of the path so an API 28 build is not reused for API 27.
BUILD="/tmp/fbv-android-occt/${PLATFORM}/${ABI}"
INSTALL="$BUILD/occt-install"
PROBE_BUILD="$BUILD/probe"
mkdir -p "$BUILD"

if [[ ! -f "$INSTALL/lib/cmake/opencascade/OpenCASCADEConfig.cmake" ]]; then
  cmake -G Ninja \
    -S "$SRC" -B "$BUILD/occt-build" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="$PLATFORM" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DBUILD_LIBRARY_TYPE=Shared \
    -DINSTALL_DIR_LAYOUT=Unix \
    -DINSTALL_DIR_WITH_VERSION=OFF \
    -DBUILD_MODULE_Draw=OFF \
    -DBUILD_MODULE_Visualization=OFF \
    -DBUILD_MODULE_DETools=OFF \
    -DBUILD_MODULE_FoundationClasses=ON \
    -DBUILD_MODULE_ModelingData=ON \
    -DBUILD_MODULE_ModelingAlgorithms=ON \
    -DBUILD_MODULE_ApplicationFramework=OFF \
    -DBUILD_MODULE_DataExchange=OFF \
    -DBUILD_DOC_Overview=OFF \
    -DBUILD_Inspector=OFF \
    -DBUILD_SAMPLES_QT=OFF \
    -DUSE_FREETYPE=OFF \
    -DUSE_TK=OFF \
    -DUSE_FREEIMAGE=OFF \
    -DUSE_FFMPEG=OFF \
    -DUSE_TBB=OFF \
    -DUSE_RAPIDJSON=OFF \
    -DUSE_DRACO=OFF \
    -DUSE_EIGEN=OFF \
    -DUSE_OPENGL=OFF \
    -DUSE_GLES2=OFF \
    -DUSE_XLIB=OFF \
    -DUSE_D3D=OFF
  cmake --build "$BUILD/occt-build" --parallel "$(nproc)"
  cmake --install "$BUILD/occt-build"
fi

cmake -G Ninja \
  -S "$ROOT/tools/android_occt_probe" -B "$PROBE_BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" \
  -DANDROID_PLATFORM="$PLATFORM" \
  -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release \
  -DOpenCASCADE_DIR="$INSTALL/lib/cmake/opencascade"
cmake --build "$PROBE_BUILD" --parallel "$(nproc)"

READELF="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
PROBE="$PROBE_BUILD/occt_probe"
echo "abi=$ABI"
echo "platform=$PLATFORM"
echo "ndk=$NDK"
echo "probe=$PROBE"
echo "probe_bytes=$(stat -c %s "$PROBE")"
echo "needed:"
"$READELF" -d "$PROBE" | sed -n 's/.*NEEDED.*\[\(.*\)\].*/  \1/p'
echo "android_notes:"
"$READELF" -n "$PROBE" | sed -n '1,40p'
echo "occt_shared_libraries:"
find "$INSTALL/lib" -name '*.so' -printf '%s %p\n' | sort -n
echo "occt_shared_bytes=$(find "$INSTALL/lib" -name '*.so' -printf '%s\n' | awk '{s+=$1} END {print s+0}')"

if [[ "$RUN" -eq 1 ]]; then
  ADB="$SDK/platform-tools/adb"
  if [[ ! -x "$ADB" ]]; then
    echo "adb missing: $ADB" >&2
    exit 2
  fi
  SERIAL="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  if [[ -z "$SERIAL" ]]; then
    echo "no adb device; binary was built and not run" >&2
    exit 3
  fi
  DEST="/data/local/tmp/fbv-occt-probe-$ABI"
  "$ADB" -s "$SERIAL" shell "mkdir -p $DEST"
  "$ADB" -s "$SERIAL" push "$PROBE" "$DEST/occt_probe" >/dev/null
  # Shared OCCT libraries and the NDK C++ runtime. The probe is not run on the host.
  find "$INSTALL/lib" -name '*.so' -exec "$ADB" -s "$SERIAL" push {} "$DEST/" \; >/dev/null
  STL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib"
  case "$ABI" in
    arm64-v8a) STL="$STL/aarch64-linux-android/libc++_shared.so" ;;
    x86_64) STL="$STL/x86_64-linux-android/libc++_shared.so" ;;
  esac
  "$ADB" -s "$SERIAL" push "$STL" "$DEST/libc++_shared.so" >/dev/null
  "$ADB" -s "$SERIAL" shell "chmod 755 $DEST/occt_probe && cd $DEST && LD_LIBRARY_PATH=$DEST ./occt_probe $DEST/box.bin"
fi
