# M0. Прототип on-device OCCT и бенчмарк конвертера

Статус on-device: полный прототип M0 (STEP через XDE, два устройства, три модели, FPS) **не выполнялся**. Отдельно собраны библиотеки моделирования OCCT 7.8.1 под Android NDK и выполнен один прогон коробки. Формат `brep.pack` не менялся.

Бенчмарк конвертера на ПК — вывод `fbvconv --stats --json <файл>`. Это не замер on-device OCCT из таблицы ниже, а числа для выбора мешера и оценки памяти на хосте. Поля JSON:

| Поле | Смысл |
| --- | --- |
| `elements`, `with_mesh`, `failed`, `without_geometry` | Все элементы, с мешем, с представлением но без меша, без представления |
| `triangles` | Треугольники lod0 |
| `completeness` | `ok`, если GlobalId IfcElement не потерян |
| `peak_rss_bytes` | Пик RSS процесса (`ru_maxrss` / `PeakWorkingSetSize`) |
| `mesh_bytes_peak` | Пик байт треугольников, которые конвертер держал в RAM |
| `mesh_budget_bytes` | Бюджет, после которого меш элемента сбрасывается на диск |
| `max_threads`, `max_memory_mb` | Как вызвали `--max-threads` и `--max-memory` (`max_memory_mb` = -1 — бюджет по умолчанию 64 МБ) |
| `warning_reasons` | Счётчики причин предупреждений (`no_representation`, `no_triangulation`, `boolean_failed`, `unsupported_profile`, `zero_size`, `unsupported_solid`, `mesher_failed`, `opening_not_subtracted`, `lod_dropped`, `unsupported_property`) |
| `failures` | До 64 записей `{guid, ifc_class, reason, detail}`; хвост — `failures_omitted` |
| `package_bytes` | Размер пакета |
| `timings_s.parse`, `.geometry`, `.write`, `.total` | Секунды |
| `mesher`, `geometry_kernel`, `threads` | Какой мешер отработал и сколько потоков получил итератор |

Атрибутный разбор держит текст IFC в памяти. IfcOpenShell открывает тот же путь с диска и тоже держит модель. Треугольники сверх `mesh_budget_bytes` пишутся во временные файлы и убираются из RAM; в GLB они попадают по одному элементу уже со сдвигом local origin. Итератор IfcOpenShell после триангуляции удаляет B-Rep элемента (патч в суперсборке) и не копит очередь готовых элементов шире числа потоков. Потоки задают `--threads` и `--max-threads`. Пик RSS по-прежнему включает разобранный IFC и формы, которые прямо сейчас считаются в рабочих потоках: одна тяжёлая форма может быть большой, но весь файл форм больше не живёт одновременно. Пакет пишется в каталог поэтапно, а не одним буфером.

Крупные частные модели в репозиторий не входят. Ниже замер хоста до ограничения памяти (Windows, не эта среда). Повторить его здесь нельзя; новый пик подтвердит только прогон тех же файлов.

| Модель | Время | Пик RAM | С мешем | Прочее |
| --- | ---: | ---: | ---: | --- |
| 23 МБ IFC2x3 | 17.6 с | 0.63 ГБ | 736/738 | |
| 128 МБ IFC4 | 158 с | 3.0 ГБ | 3307/3321 | |
| 723 МБ IFC4 | 1029 с | ~24 ГБ | 1507/1618 | 111 сбоев, 2.1 млн треугольников, пакет 375 МБ; геометрия 942 с (93%) |

Прогон `linux-gcc-ifcopenshell` (Release, 4 потока, допуск 0.01 м). Образцы IfcOpenShell/files (`20a17fc`) и файлы из `testdata/`. `sample_wall` — 3/4, потому что у прокси нет представления (`failed` = 0). Остальные — все элементы с телом получили меш, `completeness` = ok.

| Файл | Схема | Байт | with_mesh | failed | Треугольники | Геометрия, с | Пик RSS, МБ |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| polyline_ifc2x3.ifc | IFC2X3 | 1024 | 1/1 | 0 | 12 | 0.014 | 42.6 |
| faceted_brep.ifc | IFC2X3 | 14810 | 1/1 | 0 | 212 | 0.024 | 43.7 |
| mapped_circle.ifc | IFC2X3 | 5546 | 4/4 | 0 | 128 | 0.014 | 43.7 |
| trimmed_polyline.ifc | IFC2X3 | 7460 | 5/5 | 0 | 15740 | 0.058 | 59.0 |
| acad2010_walls.ifc | IFC2X3 | 26810 | 8/8 | 0 | 168 | 0.015 | 44.4 |
| brep_box.ifc | IFC4 | 1634 | 1/1 | 0 | 12 | 0.014 | 43.3 |
| mapped_box.ifc | IFC4 | 1861 | 1/1 | 0 | 12 | 0.013 | 43.4 |
| basic_shape_Brep.ifc | IFC4 | 6207 | 1/1 | 0 | 12 | 0.013 | 42.9 |
| basic_shape_SweptSolid.ifc | IFC4 | 5474 | 1/1 | 0 | 12 | 0.013 | 43.2 |
| mapped_shape_representation.ifc | IFC4 | 6689 | 1/1 | 0 | 12 | 0.014 | 43.7 |
| advanced_brep.ifc | IFC4 | 10707 | 1/1 | 0 | 328 | 0.015 | 45.7 |
| WallInstance_IFC4Add2.ifc | IFC4 | 26476 | 5/5 | 0 | 136 | 0.045 | 49.4 |
| sample_wall.ifc | IFC4 | 4631 | 3/4 | 0 | 36 | 0.014 | 44.1 |

# Прототип on-device OCCT

ТЗ (этап M0) требует сборку OCCT 7.8.1 под Android NDK, импорт STEP через XDE на устройстве и сравнение с заранее сконвертированным GLB в Filament. Нужны не меньше двух устройств и трёх моделей (малая / средняя / крупная). STEP, XDE и Filament в этой проверке не запускались. Решения go/no-go по объёму OCCT на телефоне нет. Числовые цели раздела 9 ТЗ остаются допущениями [П].

Пресет CMake `android-arm64` подключает toolchain NDK (`ANDROID_NDK_HOME`) и останавливается с понятной ошибкой, если NDK нет. Superbuild хоста описан в `deps/CMakeLists.txt` и включается `FBV_WITH_IFCOPENSHELL`. Он не является Android-сборкой.

## Проверка OCCT 7.8.1 на Android

Скрипт `tools/android_occt_probe/build_android.sh` качает метку OCCT `V7_8_1` (sha256 `7321af48c34dc253bf8aae3f0430e8cb10976961d534d8509e72516978aa82f5`) и собирает разделяемые библиотеки модулей FoundationClasses, ModelingData и ModelingAlgorithms. Draw, Visualization, DataExchange и ApplicationFramework выключены, поэтому TKDESTEP и XDE в замер не входят. Проба `occt_probe` строит коробку 1×2×3 м, считает точный объём и площадь и записывает форму через BinTools во временный файл, который тут же удаляет. В пакет `.fbvpkg` эта запись не попадает.

Сборка: NDK `28.2.13676358` (Clang 19.0.1), тот же NDK, что закреплён во Flutter 3.44. `ANDROID_PLATFORM=android-28`. В заметке ELF первый dword равен `0x1c`, то есть API 28. Это не minSdk приложения: в `app/android/app/build.gradle.kts` стоит `maxOf(24, flutter.minSdkVersion)`, у Flutter 3.44 это 24. Пресет `android-arm64` по-прежнему задаёт `android-26`.

| Что измерено | arm64-v8a, только сборка | x86_64, сборка и прогон |
| --- | ---: | ---: |
| Сумма всех собранных `libTK*.so` | 36 977 664 байт | 39 346 584 байт |
| Девять `libTK*.so`, которые проба реально загружает | 19 462 072 байт | 21 141 176 байт |
| `libc++_shared.so` из NDK | 9 236 352 байт | 8 808 664 байт |
| Сам `occt_probe` | 176 424 байт | 164 912 байт |

Загружаемые библиотеки пробы: `libTKernel.so`, `libTKMath.so`, `libTKG2d.so`, `libTKG3d.so`, `libTKGeomBase.so`, `libTKBRep.so`, `libTKGeomAlgo.so`, `libTKTopAlgo.so`, `libTKPrim.so`, плюс `libc.so`, `libm.so`, `libdl.so`, `liblog.so` и `libc++_shared.so`. Freetype, OpenGL и TBB в этой сборке нет. `libTKBO.so`, `libTKShHealing.so`, `libTKMesh.so` и соседние библиотеки модуля собраны и входят в первую строку таблицы, но эта проба их не загружала.

Прогон x86_64. Эмулятор Android SDK 37.2.13, API 28, Android 9, ABI `x86_64`, модель «Android SDK built for x86_64», hardware `ranchu`. Эмулятор поднял гостевую память до 1536 МБ. Это не устройство уровня Galaxy Note 10+ и не arm64. Вывод пробы: `volume_m3=6`, `area_m2=22`, `bintools_bytes=4494`, `elapsed_us=704`, `rss_hwm_kb=12892`. Объём и площадь совпали с точными 6 м³ и 22 м² до и после чтения BinTools. 704 мкс и 12 892 КБ — время и пик RSS этого процесса на одной коробке, не на модели здания.

Прогон arm64. Образ API 28 `system-images;android-28;google_apis;arm64-v8a` по-прежнему не запускается эмулятором 37.2.13 на хосте x86_64: `Avd's CPU Architecture 'arm64' is not supported`. Тот же исходный текст пробы собран отдельно с `--platform android-27` (каталог сборки включает платформу, установка API 28 не переиспользовалась). В заметке ELF первый dword равен `0x1b`, API 27. Размеры этой сборки: все `libTK*.so` 36 977 664 байт, девять загружаемых 19 462 072 байт, `libc++_shared.so` 9 236 352 байт, `occt_probe` 176 400 байт. Эмулятор 35.1.21.0 (build 12325540) на том же хосте x86_64 включил образ `system-images;android-27;default;arm64-v8a`. Гость: Android 8.1.0, `ro.build.version.sdk=27`, `ro.product.cpu.abi=arm64-v8a`, `uname -m` = `aarch64`, модель «Android SDK built for arm64», hardware `ranchu`, MemTotal 1 530 220 КБ. Это перевод arm64 на x86_64, не телефон и не API 28 из ОВ-2. Вывод пробы: `volume_m3=6`, `area_m2=22`, `bintools_bytes=4494`, `elapsed_us=111726`, `rss_hwm_kb=13188`. Объём и площадь снова совпали с 6 м³ и 22 м². 111 726 мкс и 13 188 КБ — одна коробка на этом эмуляторе. Линкер гостя напечатал предупреждения `unused DT entry` у `libc++_shared.so`; процесс после этого вывел строку `ok` и завершился с кодом 0. Бинарник API 28 arm64 по-прежнему только собран.

Таблица ниже остаётся пустой: колонки STEP, триангуляции модели и FPS не измерялись.

Когда прогон появится, отчёт заполняется так:

| Модель | Устройство | Загрузка STEP, с | Пик RSS, МБ | Триангуляция, с | FPS | Размер .so, МБ |
| --- | --- | --- | --- | --- | --- | --- |
| малая | | | | | | |
| средняя | | | | | | |
| крупная | | | | | | |

Рядом — те же модели, открытые как GLB в Filament, и вывод: оставляем ли на устройстве только чтение `brep.pack` (рекомендация риска R1) или допускаем on-device STEP.
