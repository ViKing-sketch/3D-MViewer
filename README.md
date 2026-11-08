# Field BIM Viewer

Офлайн-просмотрщик BIM/CAD для полевого инженера. Конвертер на ПК собирает пакет `.fbvpkg` (меш GLB, SQLite, точная геометрия). Телефон открывает пакет без сети.

Нормативные документы:

* [Техническое задание v0.2](docs/TZ_Field_BIM_Viewer_v0_2.md)
* [Формат пакета format_version 1](docs/package_format.md)
* [Принятые решения и статус M0](docs/decisions.md)
* [Матрица требований](docs/requirements_matrix.md)
* [Очередь приоритетов](docs/priority_plan.md)
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

По умолчанию конвертер читает IFC своим разборщиком и строит меш выдавливанием (прямоугольник, окружность, полилиния, в том числе профиль IFC4 с `ProfileName`). Пресет `linux-gcc-ifcopenshell` и Windows-пресеты `windows-msvc-ifcopenshell` / `windows-vs2026` собирают IfcOpenShell 0.8.5 с ядром Open CASCADE 7.8.1: итератор геометрии становится основным мешером, аналитический путь остаётся запасным. Первый запуск CMake компилирует OCCT и занимает много времени; повторный запуск берёт уже установленный префикс в каталоге сборки. STEP/IGES завершаются с кодом 2 и пояснением, что нужен OCCT XDE. На Android оболочка рисует пакет через Filament; на desktop слот рендера остаётся текстовым.

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

Полезные флаги: `--no-brep`, `--class IfcWall,IfcSlab`, `--linear-deflection`, `--angular-deflection`, `--lod`, `--mesher auto|ifcopenshell|analytic`, `--threads`, `--max-threads`, `--max-memory`, `--stats`, `--json <файл|->`, `--allow-incomplete`, `--validate`.

Сборка с IfcOpenShell (нужны пакеты Boost: system, program_options, regex, thread, date_time, iostreams, locale, а также `libeigen3-dev`, `libgl1-mesa-dev` и `libegl1-mesa-dev`: IfcOpenShell требует Eigen, отдельные toolkit обмена OCCT тянут TKV3d). Заголовочные части Boost (logic, uuid, scope_exit и остальные, которые реально включает IfcOpenShell) на Linux приходят с `libboost-dev`. На Windows их ставит манифест `vcpkg.json`:

```bash
cmake --preset linux-gcc-ifcopenshell
cmake --build --preset linux-gcc-ifcopenshell
ctest --preset linux-gcc-ifcopenshell --output-on-failure
./build/linux-gcc-ifcopenshell/converter/fbvconv model.ifc -o /tmp/model.fbvpkg --stats --json /tmp/model.json
```

Число потоков OCCT на первом configure задаётся `-DFBV_SUPERBUILD_JOBS=N` (пусто — все ядра). Пик RSS, пик байт меша в RAM и тайминги parse/geometry/write пишет `--stats` и `--json` (`peak_rss_bytes`, `mesh_bytes_peak`, `warning_reasons`). `--threads` задаёт потоки итератора, `--max-threads` ограничивает и это значение, и автовыбор по ядрам. `--max-memory <МБ>` — сколько байт треугольников держать в RAM, прежде чем сбросить остальные на диск (0 сбрасывает каждый элемент; без флага бюджет 64 МБ). Тот же предел режет число потоков OCCT примерно до одного на 512 МБ, но не ниже двух, если явно не просить один поток: однопоточный итератор IfcOpenShell останавливается на первом сбое. Код 4 — в пакет не попал GlobalId исходного элемента; `--allow-incomplete` всё равно записывает пакет и перечисляет пропуски в логе.

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

Boost и Eigen ставятся из манифеста `vcpkg.json` (динамический CRT, триплет `x64-windows`). В списке не только библиотеки, которые линкует `find_package` (system, program_options, regex, thread, date_time, iostreams, locale), но и заголовки, которые IfcOpenShell реально включает: logic, uuid, scope_exit, optional, algorithm, lexical_cast, variant, multi_index, circular_buffer, dynamic_bitset, smart_ptr, property_tree, function, foreach, math, range, mpl, functional, preprocessor, unordered, random. Отдельный `vcpkg install` со списком пакетов не нужен: toolchain в режиме манифеста ставит зависимости при configure.

```bat
cmake --preset windows-vs2026 -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake -DVCPKG_TARGET_TRIPLET=x64-windows
cmake --build --preset windows-vs2026 --config Release
ctest --preset windows-vs2026 -C Release --output-on-failure
build\windows-vs2026\converter\Release\fbvconv.exe model.ifc -o %TEMP%\model.fbvpkg --stats --json %TEMP%\model.json --max-threads 4 --max-memory 4096
```

Если Boost уже находится через `find_package` без vcpkg, toolchain-файл не нужен: достаточно `cmake --preset windows-vs2026`. Первый configure собирает Open CASCADE 7.8.1 в Release и ставит его в `build\windows-vs2026\occt-install`. CMake 4.x иначе отклоняет `cmake_minimum_required` OCCT ниже 3.5; суперсборка передаёт `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`. Собирайте конфигурацию **Release**: импортируемые библиотеки OCCT ставятся только для неё. Параллелизм суперсборки: `-DFBV_SUPERBUILD_JOBS=8`. DLL OCCT копируются рядом с `fbvconv.exe` после линковки. Патч IfcOpenShell (конструктор `profile_point` для MSVC 19.50 + Boost 1.92 и сброс форм OCCT по элементу) накладывается при configure и повторяется на чистом дереве FetchContent.

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

Нужен Flutter 3.44 или новее (проверено на 3.44.1 / Dart 3.12.1 и на 3.47) и системная `libsqlite3` на Linux (`sudo apt install libsqlite3-0`). На Android SQLite берётся из `sqlite3_flutter_libs` 0.5.x (`libsqlite3.so` в APK). Пакет 0.6.0+eol пустой и не подходит.

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d linux
flutter build apk --debug --target-platform android-arm64,android-x64
```

Сборка APK требует Android SDK platform 37 (его требует Filament 1.77.3), build-tools 36, NDK 28.2 и CMake 3.22. Пакет SDK называется `platforms;android-37.0`: в `app/android/app/build.gradle.kts` стоит `compileSdk { version = release(37) { minorApiLevel = 0 } }`, а не `compileSdk = 37` (тот ищет каталог `android-37`). ABI в пакете — `arm64-v8a` и `x86_64`. Распаковка `.fbvpkg` идёт в отдельном изоляте с прогрессом. На устройстве до 3 ГиБ ОЗУ lod0 крупнее 96 МиБ заменяется потоковой загрузкой GLB элементов и коробочными прокси. Крупный lod0, который влезает в бюджет, сначала рисуется коробками, затем читается по одному файлу на кадр вне UI-потока. Back отменяет распаковку между чанками и загрузку меша, затем уничтожает экземпляр материала и сам движок до закрытия страницы. На узком экране свойства открываются шторкой или боковой панелью, а дерево — отдельной вкладкой; вкладка 3D при этом не уничтожается, чтобы догрузка заглушки шла в ту же сцену. В альбомной ориентации панель камеры — узкая вертикальная полоса, а строка поиска сохраняется при повороте. Заглушки перечислены в дереве. Автокадр целится в ядро модели: далёкие выбросы не раздувают коробку, углы оставшейся коробки ставятся в поле зрения 45°, а в портрете кадр строится над шторкой. Коробочные заглушки в расчёт всей сцены не входят, а выбранная заглушка кадрируется по большему из коробочных и сеточных габаритов и включает рентген, чтобы соседи не закрывали её. После загрузки коробочный предпросмотр освобождается.

На Android импорт идёт через системный выбор файла (SAF) или «Открыть с помощью» / «Поделиться»: пакет копируется в хранилище приложения, общий каталог Android 11+ напрямую не читается. Жесты 3D — в окне Filament; дерево выбора с ним синхронизировано. Фильтр этажа, класса и материала скрывает остальные элементы и в дереве, и в сцене; кадр строится по видимому. Поиск идёт по FTS5, включая текст свойств: в сцене остаются совпадения, одно совпадение выбирается.

Чтобы смоук-тест FFI открыл `libfbv_core.so`, сначала соберите ядро и передайте путь:

```bash
FBV_CORE_LIB="$PWD/../build/linux-gcc/core/libfbv_core.so" flutter test
```

В приложении: на desktop «Сканировать» обходит каталог (подкаталоги с `manifest.json` и файлы `.fbvpkg`), «Открыть образец» берёт встроенный пакет. На Android пакет выбирается кнопкой «Импорт пакета» или входящим intent и копируется в каталог приложения. Карточка модели — дерево, свойства, фильтр класса, поиск, спецификация, экспорт CSV и, на Android, сцена Filament. Переключатели темы и языка — кнопки в углу.

Повторно собрать образец после изменений конвертера: `tools/regen_sample.sh`.

## Что проверяют тесты

* SHA-256, CRC32, JSON, ZIP STORE.
* Образец IFC в миллиметрах со сдвигом около 10 км: локальный origin, bbox стены, русские свойства, количества в метрах, классификатор, элемент без геометрии.
* Призма по полилинии, заголовок IFC2X3, фильтр `--class`, пакет без B-Rep, отказ STEP.
* `pkg_validate` и отказ открыть пакет с испорченным GLB.
* Виджеты Flutter и чтение того же пакета через C API.
