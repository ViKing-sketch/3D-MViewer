# Архитектура

Схема повторяет согласованный гибрид из раздела 6 ТЗ.

```mermaid
flowchart TB
  subgraph desk [ПК / CI: C++17, CMake]
    ifc[IFC / IfcOpenShell]
    step[STEP / IGES / OCCT XDE]
    norm[Нормализация: метры, local origin, элементы]
    brep[B-Rep по элементам]
    mesh[Меш, LOD, GLB]
    meta[meta.sqlite]
    writer[pkg_writer / pkg_validate]
    ifc --> norm
    step --> norm
    norm --> brep
    norm --> mesh
    norm --> meta
    brep --> writer
    mesh --> writer
    meta --> writer
  end
  writer -->|файл, USB, MDM, без сети| pkg[.fbvpkg]
  subgraph phone [Android / iOS]
    ui[Flutter: список, дерево, свойства, поиск]
    core[fbv_core: SQLite, B-Rep, измерения]
    fil[Filament: меш, LOD, picking]
    pkg --> core
    pkg --> fil
    ui -->|dart:ffi| core
    ui -->|platform channel| fil
    fil <-->|ElementId| core
  end
```

Тяжёлая работа (разбор IFC/STEP, булевы операции, триангуляция) остаётся на ПК. Устройство открывает готовый пакет.

В текущем коде путь IFC — встроенный парсер и аналитический мешер, а не IfcOpenShell/OCCT. STEP на конвертере отклоняется с указанием включить OCCT XDE. На устройстве `fbv_core` читает пакет и SQLite; ленивая B-Rep OCCT и Filament ещё не подключены. Состав пакета — [package_format.md](package_format.md), статус решений — [decisions.md](decisions.md).
