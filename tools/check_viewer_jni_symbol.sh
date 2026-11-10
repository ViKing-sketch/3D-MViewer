#!/bin/sh
# The viewer class is com.fieldbim.field_bim_viewer.OcctProbe. JNI encodes '_' as
# '_1', so the arm64 library must export this exact symbol. The name without
# that encoding loads and then throws UnsatisfiedLinkError.
set -eu

symbols="Java_com_fieldbim_field_1bim_1viewer_OcctProbe_nativeRun Java_com_fieldbim_field_1bim_1viewer_OcctProbe_nativeReadBrep"
bad_symbols="Java_com_fieldbim_field_bim_viewer_OcctProbe_nativeRun Java_com_fieldbim_field_bim_viewer_OcctProbe_nativeReadBrep"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
so=${1:-"$root/app/android/app/src/main/jniLibs/arm64-v8a/libocct_probe_jni.so"}

if [ ! -f "$so" ]; then
  echo "missing $so" >&2
  exit 1
fi

nm=${NM:-nm}
defs=$("$nm" -D --defined-only "$so")
for symbol in $symbols; do
  printf '%s\n' "$defs" | grep -E "[[:space:]]${symbol}\$" >/dev/null || {
    echo "arm64 $so does not export ${symbol}" >&2
    printf '%s\n' "$defs" | grep Java_ || true
    exit 1
  }
  echo "jni symbol ok: ${symbol}"
done
for bad in $bad_symbols; do
  if printf '%s\n' "$defs" | grep -E "[[:space:]]${bad}\$" >/dev/null; then
    echo "arm64 $so still exports the unescaped symbol ${bad}" >&2
    exit 1
  fi
done
