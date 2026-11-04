# Лицензии

Лицензия собственного кода Field BIM Viewer в этом репозитории не выбрана. Ниже — то, что уже попало в сборку, и то, что ТЗ требует учесть до мобильной поставки (NFR-13, риск R4, задача Z22).

| Компонент | Где | Лицензия | Как попадает в поставку |
| --- | --- | --- | --- |
| SQLite 3.49.2 amalgamation | `third_party/sqlite` | Public domain | Статически в `fbvconv`, `pkg_validate` и `libfbv_core.so` |
| Flutter / Dart | `app/` | BSD | Оболочка |
| OCCT 7.8.1 | FetchContent, префикс сборки `occt-install` | LGPL-2.1 + exception | Общая библиотека, модули моделирования и обмена, без Draw и Visualization. Только конвертер на ПК/CI |
| IfcOpenShell 0.8.5 (`481676e`) | FetchContent, схемы 2x3, 4, 4x3_add2 | LGPL-3.0 | Статически в `fbvconv` вместе с динамическим OCCT. В мобильное приложение не включать |
| Filament 1.77.3 | Android `PlatformView`, Maven `filament-android` / `gltfio-android` / `filament-utils-android` | Apache-2.0 | Динамические библиотеки в APK (`arm64-v8a`, `x86_64`), не в `libfbv_core` |
| meshoptimizer, zstd | ещё не подключены | MIT / BSD | Конвертер, LOD и сжатие B-Rep |

Экран «О программе» в оболочке перечисляет офлайн-режим и версию 0.1.0. Полный текст NOTICE для OCCT и IfcOpenShell добавляется вместе с их сборкой.
