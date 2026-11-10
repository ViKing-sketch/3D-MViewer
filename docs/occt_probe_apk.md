# Тестовый APK с пробой OCCT

Это не просмотрщик и не релиз. Файл `tools/occt_probe_apk/field-bim-occt-probe-arm64.apk` — отладочный пакет только для `arm64-v8a`, `versionName` `0.2-probe`, `targetSdk` 34. Внутри исполняемый файл пробы (в пакете он называется `libocct_probe.so`, интерпретатор `/system/bin/linker64`, метка ELF API 28) и библиотека `libocct_probe_jni.so` с тем же замером. Рядом девять библиотек OCCT и `libc++_shared.so`. Замер — ящик 1×2×3 м, ожидаемые объём 6 м³ и площадь 22 м². С этой машины пакет на телефон не ставился.

## Прогон на телефоне

Виктор поставил `0.2-probe` (коммит `16ddfaa`) на свой телефон: Android 12, `sdk=31`, `abis=arm64-v8a,armeabi-v7a,armeabi`, у установленного пакета `targetSdk=34`. Play Защита установку не блокировала.

Оба запуска завершились с `exit=0`. Объём 6 м³, площадь 22 м², файл BinTools 4494 байт. Это тот же результат, что раньше был на эмуляторе, но здесь это телефон arm64, Android 12.

Кнопка «Запустить пробу» выполнила `libocct_probe.so` из `nativeLibraryDir`. Stderr пустой. Stdout: `marker exe_init`, `marker main before_occt`, `marker box`, `marker volume 6.000000`, `marker area 22.000000`, `marker bintools_write bytes=4494`, `marker bintools_read`, `marker roundtrip`, затем `ok volume_m3=6 area_m2=22 bintools_bytes=4494 elapsed_us=1698 rss_hwm_kb=13356`.

Кнопка «JNI System.loadLibrary» загрузила `libocct_probe_jni.so` в отдельном процессе: `loadLibrary ok`, те же маркеры и `ok volume_m3=6 area_m2=22 bintools_bytes=4494 elapsed_us=1455 rss_hwm_kb=99120`.

OCCT и BinTools на этом arm64 Android 12 работают обоими способами. Предыдущий `exit=139` с пустым stdout был из-за запуска копии из `files/`: тот пакет возвращал код первой попытки и до файла в `nativeLibraryDir` не доходил. Тот же замер в просмотрщике грузится через `System.loadLibrary` из `nativeLibraryDir`, без копии в `files/`. Как нажать и что прислать: [viewer_occt.md](viewer_occt.md). Байты BinTools в пакет `.fbvpkg` этим замером не пишутся.

## Что было не так в первом пакете

Первый пакет (`0.1-probe`, `targetSdk` 28) копировал бинарник в `filesDir` и запускал эту копию. Экран показал только `exit=139` и путь `.../files/occt_probe`.

По ELF той сборки проверено на машине сборки: у пробы, девяти `libTK*.so` и `libc++_shared.so` нет сегмента `PT_TLS`. Проверка Bionic про выравнивание TLS на arm64 относится только к файлу, у которого сегмент есть. `LD_LIBRARY_PATH` в том запуске уже указывал на `nativeLibraryDir`. Платформу линковки оставили API 28.

## Как поставить

1. Удалите старое приложение «OCCT probe», если оно осталось.
2. Скопируйте APK на телефон arm64.
3. Откройте файл и разрешите установку из этого источника, если система спросит.

Кнопка «Запустить пробу» запускает `libocct_probe.so` из `nativeLibraryDir` и ставит `LD_LIBRARY_PATH` в тот же каталог. Библиотеки извлекаются на диск (`extractNativeLibs=true`). Вторая кнопка грузит `libocct_probe_jni.so` через `System.loadLibrary` в процессе `:jni`. В `filesDir` проба больше не копируется.

Повторный запуск присылается текстом с экрана. Удачный вывод содержит `marker main before_occt`, `volume_m3=6`, `area_m2=22` и `exit=0`.
