#!/bin/sh
# Fail unless the file is a signed arm64 release APK that a phone can install.
# Prints a short note (package, version, certificate) on stdout.
set -eu

apk=${1:?usage: check_release_apk.sh <apk>}
if [ ! -f "$apk" ]; then
  echo "not a file: $apk" >&2
  exit 1
fi

unzip -t "$apk" >/dev/null

need() {
  if ! unzip -l "$apk" | grep -q "$1"; then
    echo "missing $1" >&2
    exit 1
  fi
}

need 'AndroidManifest.xml'
need 'classes.dex'
need 'resources.arsc'
need 'lib/arm64-v8a/libflutter.so'
need 'lib/arm64-v8a/libapp.so'
need 'lib/arm64-v8a/libocct_probe_jni.so'
need 'lib/arm64-v8a/libTKernel.so'

if unzip -l "$apk" | grep -q 'lib/x86_64/'; then
  echo "release APK must be arm64-v8a only" >&2
  exit 1
fi
if unzip -l "$apk" | grep -q 'kernel_blob.bin'; then
  echo "debug kernel_blob.bin is in a release APK" >&2
  exit 1
fi

python3 - "$apk" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
if b"APK Sig Block 42" not in data:
    sys.exit("no APK Signature Scheme v2/v3 block")
PY

sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [ -z "$sdk" ]; then
  echo "ANDROID_SDK_ROOT is unset; signature was checked only for the v2 block" >&2
  exit 1
fi

signer=$(find "$sdk/build-tools" -name apksigner -type f | sort | tail -n 1)
aapt=$(find "$sdk/build-tools" -name aapt -type f | sort | tail -n 1)
zipalign=$(find "$sdk/build-tools" -name zipalign -type f | sort | tail -n 1)
if [ -z "$signer" ] || [ -z "$aapt" ] || [ -z "$zipalign" ]; then
  echo "need apksigner, aapt and zipalign under $sdk/build-tools" >&2
  exit 1
fi

"$zipalign" -c 4 "$apk" >&2
"$signer" verify --print-certs "$apk" >&2

badging=$("$aapt" dump badging "$apk")
if ! printf '%s\n' "$badging" | grep -q "name='com.fieldbim.field_bim_viewer'"; then
  echo "unexpected package name" >&2
  printf '%s\n' "$badging" | sed -n '1,12p' >&2
  exit 1
fi
if ! printf '%s\n' "$badging" | grep -q "native-code: 'arm64-v8a'"; then
  echo "badging has no arm64-v8a native-code" >&2
  printf '%s\n' "$badging" | sed -n '1,20p' >&2
  exit 1
fi
if printf '%s\n' "$badging" | grep -q "x86_64"; then
  echo "badging lists x86_64" >&2
  exit 1
fi

version_line=$(printf '%s\n' "$badging" | sed -n '1p')
bytes=$(wc -c < "$apk" | tr -d ' ')
cat <<EOF
Field BIM Viewer, arm64 APK. Actions artifact, not a GitHub Release.
commit: ${GITHUB_SHA:-local}
$version_line
bytes: $bytes
Подпись: debug-ключ сборки. Keystore в репозитории нет.
EOF
