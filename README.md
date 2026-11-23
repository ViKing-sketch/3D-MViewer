# Field BIM Viewer

Офлайн-просмотрщик BIM/CAD для полевого инженера. Конвертер на ПК собирает пакет `.fbvpkg` (меш, SQLite, точная геометрия). Телефон открывает пакет без сети. Целевая платформа — Android.

## APK на телефон

Свежий release `arm64-v8a` публикуется на каждый push в `main` и вручную (Actions → Android release APK → Run workflow):

<https://github.com/ViKing-sketch/3D-MViewer/releases/download/latest/field-bim-viewer-arm64.apk>

Откройте ссылку на телефоне и подтвердите установку. Это prerelease с тегом `latest`, не Google Play. Подпись одна и та же (`tools/android_sideload`), номер сборки растёт, поэтому следующая версия ставится поверх. Если система пишет, что подпись не совпадает, удалите старое приложение один раз: ранние APK из git подписаны иначе.

## Сборка Android локально

Нужны Flutter 3.44 или новее, Android SDK platform `android-37.0`, build-tools 36 и NDK 28.2.

```bash
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Файл: `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. В git APK не кладутся.

Linux, Windows, тесты и отладочный APK — [docs/build.md](docs/build.md).

## Документы

- [Статус относительно ТЗ](docs/STATUS.md)
- [Техническое задание v0.2](docs/TZ_Field_BIM_Viewer_v0_2.md)
- [Формат пакета](docs/package_format.md)
- [Сборка](docs/build.md)
