# Формат пакета `.fbvpkg` (format_version 1 и 2)

Пакет — результат конвертера `fbvconv`. Это либо ZIP без сжатия (метод STORE), либо каталог с тем же составом. Имя файла обычно заканчивается на `.fbvpkg`. Версия задаётся полем `format_version` в `manifest.json`. Читатель обязан отвергнуть неизвестную версию.

Этот документ — нормативное описание версии 1, которую пишет текущий конвертер. Исходное ТЗ (раздел 7) — в [TZ_Field_BIM_Viewer_v0_2.md](TZ_Field_BIM_Viewer_v0_2.md). Отличия версии 1 от черновика ТЗ перечислены в конце.

## Состав

```
model.fbvpkg
├── manifest.json
├── meta.sqlite
├── mesh/
│   ├── lod0.glb
│   └── elements/
│       └── <ElementId>.glb
├── brep.pack          # если brep.codec != "none"
└── brep.index
```

`manifest.json` не входит в `parts` и не хэшируется сам собой: он содержит хэши остальных частей.

## manifest.json

```json
{
  "format_version": 1,
  "generator": "fbvconv 0.1.0",
  "created_utc": "2026-10-31T00:00:00Z",
  "name": "Sample Project",
  "source": {
    "filename": "model.ifc",
    "schema": "IFC4",
    "sha256": "<hex sha256 исходного файла>"
  },
  "units": {
    "length": "metre",
    "source_length_unit": "millimetre",
    "area": "square_metre",
    "volume": "cubic_metre",
    "ui_length": "millimetre"
  },
  "local_origin": [0.0, 0.0, 0.0],
  "world_bbox": { "min": [0, 0, 0], "max": [1, 1, 1] },
  "counts": {
    "spatial": 4,
    "elements": 4,
    "elements_with_mesh": 3,
    "elements_without_geometry": 1,
    "triangles_lod0": 36,
    "warnings": 1
  },
  "mesh": {
    "generator": "analytic-extrusion-v1",
    "linear_deflection_m": 0.01,
    "angular_deflection_rad": 0.5,
    "lods": ["lod0"],
    "instancing": false,
    "coordinate_space": "local_origin_metres_float32"
  },
  "brep": {
    "codec": "analytic-box-v1",
    "coordinate_space": "world_metres_float64"
  },
  "parts": {
    "mesh/lod0.glb": { "sha256": "<hex>", "bytes": 2048 }
  }
}
```

* Координаты меша — float32 в метрах относительно `local_origin` (минимум мирового bbox). Так крупные геодезические координаты не теряют точность в float32.
* B-Rep и `elements.bbox_*` — float64 в исходной системе после перевода в метры, без вычитания origin.
* `local_origin` — тот же сдвиг, double, метры.
* Единицы пакета — метры. Исходные единицы IFC записаны в `source_length_unit`. UI показывает длины в миллиметрах.

## Меш

`mesh/lod0.glb` — glTF 2.0 binary. Корневой узел `root`, дочерние узлы — по одному на элемент с геометрией. У каждого дочернего узла:

* `extras.elementId` — ElementId (целое, с 1);
* `mesh` — один primitive с `POSITION`, `NORMAL`, индексами `UNSIGNED_INT`;
* материал с `baseColorFactor` и `doubleSided: true`.

`elements.mesh_node` — индекс этого узла в массиве `nodes` файла `lod0.glb`. У элемента без меша поле `NULL`.

`mesh/elements/<ElementId>.glb` — тот же элемент отдельным GLB (корень + один узел с тем же `elementId`). Файл обязателен для каждого элемента, у которого `mesh_node` не NULL, и перечислен в `parts`.

Инстансинг `EXT_mesh_gpu_instancing` и LOD1/LOD2 в версии 1 не пишутся (`instancing: false`, `lods: ["lod0"]`). `mesh.generator` — `analytic-extrusion-v1`, `ifcopenshell-occt` или `ifcopenshell-occt+analytic-extrusion-v1`, если часть элементов добрана аналитическим запасным путём. Допуски триангуляции — аргументы мешера OCCT. `counts.elements_failed` — элементы с представлением, но без меша. `completeness` равен `ok`, если ни один GlobalId IfcElement из прохода IfcOpenShell не потерян.

## meta.sqlite

SQLite с FTS5. `schema_meta.format_version` равен `1` у старого пакета и `2` у нового. Таблицы ниже — общие; `systems` и `system_elements` есть только у версии 2, см. раздел format_version 2.

| Таблица | Назначение |
| --- | --- |
| `spatial` | `id`, `kind` (`Project`/`Site`/`Building`/`Storey`/`Space`), `name`, `elevation` (м), `parent_id` |
| `types` | `id`, `guid`, `ifc_class`, `name`, `predefined_type` |
| `elements` | `id` ElementId, `guid`, `ifc_class`, `name`, `tag`, `type_id`, `storey_id`, `parent_id` (узел `spatial`), `material_set_id`, bbox мира float64, `mesh_node`, `brep_ref`, `color_r/g/b` |
| `psets` / `props` | `psets.source` = `instance` или `type`. Свойства типа лежат один раз с `type_id` |
| `quantities` | `kind`: `Length`/`Area`/`Volume`/`Count`/`Weight`. Длины в метрах, площади в м², объёмы в м³ |
| `materials`, `material_sets`, `material_layers` | Слой: `set_id`, `material_id`, `thickness` (м), `layer_order` |
| `classification` | `system`, `code`, `title` |
| `assembly` | Зарезервировано под дерево STEP/XDE, в IFC-пакете пусто |
| `spec_views` | Сводки: число элементов и суммы количеств по этажу, классу, типу и материалу |
| `fts_elements` | FTS5 `unicode61`: имя, марка, guid, имя типа, текст свойств |

`material_layers.layer_order` — это поле `order` из раздела 7.1 ТЗ: имя `order` в SQLite занято.

## brep.pack / brep.index

Маленький порядок байт (little-endian).

`brep.codec = "none"` — файлов нет, `elements.brep_ref` пуст.

`brep.codec = "analytic-box-v1"`:

`brep.pack`:

| Смещение | Тип | Значение |
| --- | --- | --- |
| 0 | char[4] | `FBVB` |
| 4 | uint32 | version = 1 |
| 8 | uint32 | count |
| далее записи | | |
| +0 | uint32 | kind = 1 (AABB мира, метры) |
| +4 | float64[3] | min xyz |
| +28 | float64[3] | max xyz |

`brep.index`:

| Смещение | Тип | Значение |
| --- | --- | --- |
| 0 | char[4] | `FBVI` |
| 4 | uint32 | version = 1 |
| 8 | uint32 | count |
| далее записи по 124 байта | | |
| +0 | int64 | ElementId |
| +8 | uint64 | смещение записи в `brep.pack` |
| +16 | uint64 | длина записи |
| +24 | uint32 | codec = 1 |
| +28 | float64[12] | матрица 3×4, для AABB — единичная (геометрия уже в мире) |

`elements.brep_ref` — номер записи с нуля.

Это не BinTools OCCT. `format_version` 2 занят таблицами систем, а не B-Rep. Когда появится OCCT, кодек `bintools-zstd-v1` потребует следующую `format_version`, если разметка записи станет несовместимой. Читатель открывает пакет с неизвестным кодеком (свойства доступны) и возвращает ошибку на запрос точной геометрии.

## ZIP

Метод STORE, флаг UTF-8 (бит 11), без ZIP64. Имена с `/`, без `..`. Каталог и ZIP равноправны: `fbv_package_open` и `pkg_validate` принимают оба. При открытии ZIP SQLite и меши распаковываются во временный каталог; потоковое чтение STORE по смещению — следующая оптимизация для крупных пакетов.

## format_version 2

Новый пакет пишет `format_version` 2. Читатель открывает 1 и 2. Любая другая версия — ошибка с номером версии, пакет не открывается.

Версия 1 не содержит таблиц систем. Такой пакет открывается, список систем пуст, фильтр системы в просмотре не предлагается. Читатель не переписывает пакет версии 1 и не подменяет отсутствие таблиц пустым списком у версии 2.

Версия 2 добавляет в `meta.sqlite`:

```sql
CREATE TABLE systems(
  id INTEGER PRIMARY KEY,
  guid TEXT,
  ifc_class TEXT NOT NULL,
  name TEXT,
  description TEXT
);

CREATE TABLE system_elements(
  system_id INTEGER NOT NULL,
  element_id INTEGER NOT NULL,
  PRIMARY KEY (system_id, element_id)
);
```

`schema_meta.format_version` совпадает с manifest (`1` или `2`). У версии 2 отсутствие `systems` или `system_elements` — ошибка, а не «систем нет».

Конвертер пишет `IfcSystem`, `IfcDistributionSystem` и `IfcBuildingSystem`. Состав берётся из `IfcRelAssignsToGroup`: элемент может входить в несколько систем. `IfcZone` в этот список не входит. `system_elements.element_id` — id строки `elements`, не STEP-id.

`testdata/sample_model` и `testdata/sample_wall.fbvpkg` остаются версией 1.

## Проверка

`pkg_validate <пакет>` и `fbvconv --validate <пакет>` возвращают 0, если:

* `format_version` равен 1 или 2, а `schema_meta.format_version` ему равен;
* у версии 2 есть таблицы `systems` и `system_elements`;
* каждый файл из `parts` существует, размер и SHA-256 совпадают;
* счётчики manifest совпадают с `meta.sqlite`;
* GUID элементов непусты и уникальны;
* у каждого элемента с мешем есть узел в `lod0.glb` и файл `mesh/elements/<id>.glb`;
* при кодеке `analytic-box-v1` AABB в `brep.pack` совпадает с bbox в SQLite;
* в `fts_elements` есть строка на каждый элемент.

Иначе код 3 и текст ошибок в stdout.

`fbv_package_open` тоже сверяет SHA-256 и отказывается открывать повреждённый пакет.

## Отличия от черновика раздела 7 ТЗ

| Черновик ТЗ | format_version 1 |
| --- | --- |
| Один `lod0.glb`, опционально `lod1` и тайлы | Плюс обязательный `mesh/elements/<id>.glb` для элементов с геометрией |
| `brep.pack` = BinTools + zstd | Кодек `analytic-box-v1`: мировой AABB. BinTools — следующий кодек |
| `thumbs/` | Не пишется |
| `EXT_mesh_gpu_instancing`, meshoptimizer | Не пишется, поле `instancing: false` |
