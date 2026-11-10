# Проба OCCT в просмотрщике

Это тот же замер, что в тестовом APK `0.2-probe`, встроенный в Field BIM Viewer. Библиотека `libocct_probe_jni.so` и девять `libTK*.so` лежат в `nativeLibraryDir`. Кнопка вызывает `System.loadLibrary`. В `filesDir` бинарник не копируется: такая копия на Android 12 дала `exit=139` и пустой stdout.

На телефоне Виктора (Android 12, `sdk=31`, arm64) оба способа отдельной пробы уже дали `exit=0`, объём 6 м³, площадь 22 м² и BinTools 4494 байт. С этой машины на телефон ничего не ставится.

`brep.pack` по-прежнему AABB `analytic-box-v1`. Это не точная геометрия. Замер коробки во временный файл не пишет байты в пакет.

## Прогон на телефоне

Виктор поставил просмотрщик `0.1.2` (коммит `66c4e71`) на свой телефон: Android 12, `sdk=31`, arm64, у установленного пакета `targetSdk=34`.

Кнопка «Проба OCCT» завершилась с `exit=0`. Объём 6 м³, площадь 22 м², файл BinTools 4494 байт. `launch=loadLibrary`, `files_copy=no`, `jni_bytes=52648`. В `files/` бинарник не копировался.

Маркеры: `marker main before_occt`, `marker box`, `marker volume 6.000000`, `marker area 22.000000`, `marker bintools_write bytes=4494`, `marker bintools_read`, `marker roundtrip`, затем `ok volume_m3=6 area_m2=22 bintools_bytes=4494 elapsed_us=1904 rss_hwm_kb=189164`.

Сборка `0.1.1` на том же телефоне до этого загрузила `.so` и не нашла метод: символ был `field_bim_viewer`, а JNI для пакета `field_bim_viewer` ждёт `field_1bim_1viewer`.

## Что нажать

1. Удалите просмотрщик `0.1.1`, если он установлен. Поставьте arm64 APK `tools/viewer_apk/field-bim-viewer-arm64.apk` (`0.1.2`, `targetSdk` 34).
2. Откройте Field BIM Viewer.
3. На экране моделей нажмите «Проба OCCT».
4. Дождитесь текста в окне. Его можно выделить.

## Что прислать

Повторный запуск присылается текстом из окна. Прогон `0.1.2` уже содержит `launch=loadLibrary`, `files_copy=no`, `marker main before_occt`, `ok volume_m3=6 area_m2=22 bintools_bytes=4494` и `exit=0`.
