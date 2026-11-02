# Field BIM Viewer

Офлайн-просмотрщик BIM/CAD для полевого инженера. Конвертер на ПК собирает пакет `.fbvpkg` (меш GLB, SQLite, точная геометрия). Телефон открывает пакет без сети.

Нормативные документы:

* [Техническое задание v0.2](docs/TZ_Field_BIM_Viewer_v0_2.md)
* [Формат пакета format_version 1](docs/package_format.md)
* [Принятые решения и статус M0](docs/decisions.md)
* [План Filament](docs/rendering.md)

## Состав репозитория

| Каталог | Содержание |
| --- | --- |
| `converter/` | CLI `fbvconv` и `pkg_validate` |
| `core/` | `fbv_core`, C API для `dart:ffi` |
| `app/` | Оболочка Flutter |
| `deps/` | Superbuild OCCT 7.8.1 и IfcOpenShell (опция `FBV_WITH_IFCOPENSHELL`) и toolchain Android/iOS |
| `third_party/sqlite/` | SQLite 3.49.2 amalgamation |
| `testdata/` | Образец IFC и собранный пакет |
| `docs/` | ТЗ, формат, архитектура |

По умолчанию конвертер читает IFC своим разборщиком и строит меш выдавливанием (прямоугольник, окружность, полилиния, в том числе профиль IFC4 с `ProfileName`). Пресет `linux-gcc-ifcopenshell` и Windows-пресеты `windows-msvc-ifcopenshell` / `windows-vs2026` собирают IfcOpenShell 0.8.5 с ядром Open CASCADE 7.8.1: итератор геометрии становится основным мешером, аналитический путь остаётся запасным. Первый запуск CMake компилирует OCCT и занимает много времени; повторный запуск берёт уже установленный префикс в каталоге сборки. STEP/IGES завершаются с кодом 2 и пояснением, что нужен OCCT XDE. Рендер Filament в оболочке — заглушка.

## Linux

Нужны GCC, CMake 3.21+ и Ninja.

```bash
sudo apt install build-essential cmake ninja-build
cmake --preset linux-gcc
cmake --build --preset linux-gcc
ctest --preset linux-gcc --output-on-failure
```

Релизная сборка: пресет `linux-gcc-release`.

```bash
./build/linux-gcc/converter/fbvconv testdata/sample_wall.ifc -o /tmp/sample.fbvpkg
./build/linux-gcc/converter/pkg_validate /tmp/sample.fbvpkg
./build/linux-gcc/converter/fbvconv testdata/sample_wall.ifc -o /tmp/sample_model --directory
```

Код 0 — успех, 2 — ошибка конвертации, 3 — пакет не прошёл проверку. Лог пишется рядом: `/tmp/sample.fbvpkg.log`.

Полезные флаги: `--no-brep`, `--class IfcWall,IfcSlab`, `--linear-deflection`, `--angular-deflection`, `--lod`, `--mesher auto|ifcopenshell|analytic`, `--threads`, `--stats`, `--json <файл|->`, `--allow-incomplete`, `--validate`.

Сборка с IfcOpenShell (нужны пакеты Boost: system, program_options, regex, thread, date_time, iostreams, а также `libeigen3-dev`, `libgl1-mesa-dev` и `libegl1-mesa-dev`: IfcOpenShell требует Eigen, отдельные toolkit обмена OCCT тянут TKV3d):

```bash
cmake --preset linux-gcc-ifcopenshell
cmake --build --preset linux-gcc-ifcopenshell
ctest --preset linux-gcc-ifcopenshell --output-on-failure
./build/linux-gcc-ifcopenshell/converter/fbvconv model.ifc -o /tmp/model.fbvpkg --stats --json /tmp/model.json
```

Число потоков OCCT на первом configure задаётся `-DFBV_SUPERBUILD_JOBS=N` (пусто — все ядра). Пик RSS и тайминги parse/geometry/write пишет `--stats` и `--json`. Код 4 — в пакет не попал GlobalId исходного элемента; `--allow-incomplete` всё равно записывает пакет и перечисляет пропуски в логе.

Образ Docker с тем же CLI: `docker build -t fbvconv .`

## Windows — MSVC

Visual Studio 2022 (генератор «Visual Studio 17 2022»), CMake и компилятор C++ из «Desktop development with C++». Команды — из «x64 Native Tools Command Prompt» или Developer PowerShell, где `cl` уже в `PATH`.

```bat
cmake --preset windows-msvc
cmake --build --preset windows-msvc --config Release
ctest --preset windows-msvc -C Release --output-on-failure
build\windows-msvc\converter\Release\fbvconv.exe testdata\sample_wall.ifc -o %TEMP%\sample.fbvpkg
build\windows-msvc\converter\Release\pkg_validate.exe %TEMP%\sample.fbvpkg
```

Исходники собираются с `/utf-8`.

CI гоняет пресет `windows-msvc` на образе `windows-2022` и отдельно `windows-msvc-ifcopenshell` (тот же генератор, плюс Boost из vcpkg и суперсборка OCCT). Образ `windows-latest` содержит Visual Studio 2026; генератор «Visual Studio 17 2022» на нём не находится.

## Windows — Visual Studio 2026

Нужны Visual Studio 2026 (генератор «Visual Studio 18 2026», MSVC 19.50), CMake **4.2 или новее** (в 4.2 появился этот генератор) и Boost для IfcOpenShell. Команды — из «x64 Native Tools Command Prompt for VS 2026» или Developer PowerShell, где `cl` уже в `PATH`.

Boost через vcpkg (динамический CRT, триплет `x64-windows`):

```bat
vcpkg install boost-system:x64-windows boost-program-options:x64-windows boost-regex:x64-windows boost-thread:x64-windows boost-date-time:x64-windows boost-iostreams:x64-windows eigen3:x64-windows
cmake --preset windows-vs2026 -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake
cmake --build --preset windows-vs2026 --config Release
ctest --preset windows-vs2026 -C Release --output-on-failure
build\windows-vs2026\converter\Release\fbvconv.exe model.ifc -o %TEMP%\model.fbvpkg --stats --json %TEMP%\model.json
```

Если Boost уже находится через `find_package` без vcpkg, toolchain-файл не нужен: достаточно `cmake --preset windows-vs2026`. Первый configure собирает Open CASCADE 7.8.1 в Release и ставит его в `build\windows-vs2026\occt-install`. Собирайте конфигурацию **Release**: импортируемые библиотеки OCCT ставятся только для неё. Параллелизм суперсборки: `-DFBV_SUPERBUILD_JOBS=8`. DLL OCCT копируются рядом с `fbvconv.exe` после линковки.

Пресет `windows-msvc-ifcopenshell` — то же самое генератором «Visual Studio 17 2022» (образ CI `windows-2022`).

## Windows — MSYS2 / MinGW

В среде UCRT64 (или MINGW64):

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja
cmake --preset windows-mingw
cmake --build --preset windows-mingw
ctest --preset windows-mingw --output-on-failure
```

Пресеты `windows-msvc` и `windows-mingw` видны только на Windows. Пресет `android-arm64` требует переменную `ANDROID_NDK_HOME` и относится к задаче сборки OCCT под NDK. Пресет `ios` — к будущему xcframework на macOS.

## Flutter

Нужен Flutter 3.22+ (проверено на 3.47) и системная `libsqlite3` на Linux (`sudo apt install libsqlite3-0`).

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Чтобы смоук-тест FFI открыл `libfbv_core.so`, сначала соберите ядро и передайте путь:

```bash
FBV_CORE_LIB="$PWD/../build/linux-gcc/core/libfbv_core.so" flutter test
```

В приложении: «Сканировать» обходит каталог (подкаталоги с `manifest.json` и файлы `.fbvpkg`), «Открыть образец» берёт встроенный пакет. Карточка модели — дерево, свойства, фильтр класса, поиск, спецификация и экспорт CSV. Переключатели темы и языка — кнопки в углу.

Повторно собрать образец после изменений конвертера: `tools/regen_sample.sh`.

## Что проверяют тесты

* SHA-256, CRC32, JSON, ZIP STORE.
* Образец IFC в миллиметрах со сдвигом около 10 км: локальный origin, bbox стены, русские свойства, количества в метрах, классификатор, элемент без геометрии.
* Призма по полилинии, заголовок IFC2X3, фильтр `--class`, пакет без B-Rep, отказ STEP.
* `pkg_validate` и отказ открыть пакет с испорченным GLB.
* Виджеты Flutter и чтение того же пакета через C API.
