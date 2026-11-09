#!/bin/sh
# Packs the already-built android-28 arm64 OCCT probe into a debug APK.
# Does not talk to a phone. Paths default to the cloud build that produced
# the probe; override them when the libraries live somewhere else.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
probe=${OCCT_PROBE:-/tmp/fbv-android-occt/arm64-v8a/probe/occt_probe}
libdir=${OCCT_LIBDIR:-/tmp/fbv-android-occt/arm64-v8a/occt-install/lib}
cxx=${OCCT_CXX:-/tmp/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so}
sdk=${ANDROID_SDK_ROOT:-/tmp/android-sdk}
jni=$root/app/src/main/jniLibs/arm64-v8a
rm -rf "$root/app/src/main/jniLibs"
mkdir -p "$jni"
cp "$probe" "$jni/libocct_probe.so"
cp "$cxx" "$jni/libc++_shared.so"
for name in TKernel TKMath TKG2d TKG3d TKGeomBase TKBRep TKGeomAlgo TKTopAlgo TKPrim; do
  cp "$libdir/lib${name}.so" "$jni/"
done
printf 'sdk.dir=%s\n' "$sdk" > "$root/local.properties"
gradle=$root/../../app/android/gradlew
"$gradle" -p "$root" :app:assembleDebug --offline || "$gradle" -p "$root" :app:assembleDebug
cp "$root/app/build/outputs/apk/debug/app-debug.apk" "$root/field-bim-occt-probe-arm64.apk"
echo "wrote $root/field-bim-occt-probe-arm64.apk"
