#!/bin/sh
# Пересобрать образец пакета из testdata/sample_wall.ifc.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
conv=${FBVCONV:-"$root/build/linux-gcc/converter/fbvconv"}
if [ ! -x "$conv" ]; then
  echo "Сначала соберите fbvconv (cmake --preset linux-gcc && cmake --build --preset linux-gcc)" >&2
  exit 1
fi
rm -rf "$root/testdata/sample_model"
"$conv" "$root/testdata/sample_wall.ifc" -o "$root/testdata/sample_model" --directory
"$conv" "$root/testdata/sample_wall.ifc" -o "$root/testdata/sample_wall.fbvpkg"
rm -rf "$root/app/assets/sample_model"
mkdir -p "$root/app/assets/sample_model"
cp -a "$root/testdata/sample_model/." "$root/app/assets/sample_model/"
echo "Обновлены testdata/sample_model, testdata/sample_wall.fbvpkg и app/assets/sample_model"
