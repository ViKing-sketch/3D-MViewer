# Field BIM Viewer

Офлайн-просмотрщик BIM/CAD для полевого инженера. Конвертер на ПК собирает пакет `.fbvpkg`: меш и SQLite. `brep.pack` — AABB, не точная геометрия. Отдельный слот BinTools (format v4) опционален и заполнен не всегда. Телефон открывает пакет без сети. Целевая платформа — Android.

## APK

В git APK нет. GitHub Release не используется. Workflow «Android APK» собирает arm64 и оставляет файл артефактом Actions: на push в `main` и по ручному запуску (Actions → Android APK → Run workflow). Скачать его можно со страницы прогона, пока артефакт хранится. Как отдавать пакет на телефон, не согласовано. Сборка подписана debug-ключом.

## Сборка Android локально

Нужны Flutter 3.44 или новее, Android SDK platform `android-37.0`, build-tools 36 и NDK 28.2.

```bash
cd app
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Файл: `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. В git его не класть.

Linux, Windows, тесты и отладочный APK — [docs/build.md](docs/build.md).

## Документы

- [Статус относительно ТЗ](docs/STATUS.md)
- [Техническое задание v0.2](docs/TZ_Field_BIM_Viewer_v0_2.md)
- [Формат пакета](docs/package_format.md)
- [Сборка](docs/build.md)
- [Проверка сервера по Wi-Fi](docs/server_connect_test.md)
