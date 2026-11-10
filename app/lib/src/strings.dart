class S {
  const S(this.russian);
  final bool russian;

  String get appTitle => 'Field BIM Viewer';
  String get library => russian ? 'Модели' : 'Models';
  String get scan => russian ? 'Сканировать' : 'Scan';
  String get openSample => russian ? 'Открыть образец' : 'Open sample';
  String get pathHint =>
      russian ? 'Каталог с пакетами' : 'Folder with packages';
  String get emptyLibrary =>
      russian ? 'Пакетов не найдено' : 'No packages found';
  String get properties => russian ? 'Свойства' : 'Properties';
  String get specification => russian ? 'Спецификация' : 'Specification';
  String get view3d => '3D';
  String get tree => russian ? 'Дерево' : 'Tree';
  String get standIns => russian ? 'Заглушки' : 'Stand-ins';
  String get standInHint => russian
      ? 'Нажмите, чтобы показать заглушку и загрузить её GLB'
      : 'Tap to frame a stand-in and stream its GLB';
  String get propertySearch => russian ? 'Поиск свойства' : 'Search properties';
  String get searchHint => russian
      ? 'Имя, марка, GlobalId, свойство'
      : 'Name, tag, GlobalId, property';
  String get renderStub => russian
      ? '3D-рендер Filament работает на Android. Здесь доступны дерево, свойства и спецификация.'
      : 'The Filament renderer runs on Android. The tree, properties and specification are available here.';
  String get about => russian ? 'О программе' : 'About';
  String get delete => russian ? 'Удалить' : 'Delete';
  String get deleteConfirm => russian
      ? 'Удалить пакет с устройства?'
      : 'Delete this package from the device?';
  String get cancel => russian ? 'Отмена' : 'Cancel';
  String get exportCsv => russian ? 'Экспорт CSV' : 'Export CSV';
  String get csvFolder => russian ? 'Папка для CSV' : 'Folder for the CSV';
  String get csvSave => russian ? 'Сохранить' : 'Save';
  String get theme => russian ? 'Тема' : 'Theme';
  String get language => russian ? 'Язык' : 'Language';
  String get offline => russian
      ? 'Офлайн. Сеть приложению не нужна.'
      : 'Offline. This app does not use the network.';
  String get allClasses => russian ? 'Все классы' : 'All classes';
  String get allStoreys => russian ? 'Все этажи' : 'All storeys';
  String get allMaterials => russian ? 'Все материалы' : 'All materials';
  String get allSystems => russian ? 'Все системы' : 'All systems';
  String get noMaterial => russian ? 'Без материала' : 'No material';
  String get filter => russian ? 'Фильтр' : 'Filter';
  String get filterTitle => russian
      ? 'Этаж, класс, материал, система'
      : 'Storey, class, material, system';
  String get noSelection => russian ? 'Выберите элемент' : 'Select an element';
  String get quantities => russian ? 'Количества' : 'Quantities';
  String get classification => russian ? 'Классификация' : 'Classification';
  String get elements => russian ? 'Элементы' : 'Elements';
  String get yes => russian ? 'да' : 'yes';
  String get no => russian ? 'нет' : 'no';
  String get dataSourceCore => 'fbv_core';
  String get dataSourceSqlite => 'sqlite';
  String get back => russian ? 'Назад' : 'Back';
  String get importPackage => russian ? 'Импорт пакета' : 'Import package';
  String geometryMethod(String method, String reason) => method == 'exact'
      ? (russian ? 'Геометрия: точная' : 'Geometry: exact')
      : (russian ? 'Геометрия: меш ($reason)' : 'Geometry: mesh ($reason)');

  String get occtProbe => russian ? 'Проба OCCT' : 'OCCT probe';
  String get occtProbeRunning => russian ? 'Проба OCCT…' : 'OCCT probe…';
  String get importFailed => russian
      ? 'Не удалось импортировать пакет'
      : 'Could not import the package';
  String get libraryStored => russian
      ? 'Пакеты хранятся в памяти приложения. Общая папка Android недоступна.'
      : 'Packages are kept in app storage. Android shared storage cannot be read directly.';
  String get fitAll => russian ? 'Вписать всё' : 'Fit all';
  String get fitSelected => russian ? 'Вписать выбранное' : 'Fit selected';
  String get hide => russian ? 'Скрыть' : 'Hide';
  String get showAll => russian ? 'Показать всё' : 'Show all';
  String get isolate => russian ? 'Изолировать' : 'Isolate';
  String get xray => russian ? 'Рентген' : 'X-ray';
  String get xrayHint => russian
      ? 'Остальные элементы становятся полупрозрачными. Выбранный остаётся сплошным.'
      : 'Other elements turn translucent. The selection stays solid.';
  String get menu => russian ? 'Меню' : 'Menu';
  String get section => russian ? 'Срез' : 'Section';
  String get sectionHint => russian
      ? 'Плоскость X, Y (вверх), Z или по взгляду отсекает в материале и не зависит от зума. Лицевые грани остаются освещёнными, срез — цветом обратных граней. Рентген и подсветка выбора продолжают работать. Касание не выбирает отсечённое.'
      : 'An X, Y (up), Z, or view plane clips in the material and stays put when you zoom. Front faces stay lit, and the cut is the back-face colour. X-ray and the selection highlight keep working. Taps ignore clipped geometry.';
  String get sectionNear => russian ? 'Ближняя' : 'Near';
  String get sectionOffset => russian ? 'Сдвиг' : 'Offset';
  String sectionOffsetAt(String axis, double metres) => russian
      ? '$axis · ${metres.toStringAsFixed(1)} м'
      : '$axis · ${metres.toStringAsFixed(1)} m';
  String sectionBoxMetres(double metres) => russian
      ? 'Коробка · ${metres.toStringAsFixed(1)} м'
      : 'Box · ${metres.toStringAsFixed(1)} m';
  String get sectionMore => russian ? 'Ещё' : 'More';
  String get sectionLess => russian ? 'Скрыть' : 'Less';
  String get sectionFlip => russian ? 'Сторона' : 'Side';
  String get sectionBox => russian ? 'Коробка' : 'Box';
  String get sectionBoxHint => russian
      ? 'Оставляет только объём внутри коробки'
      : 'Keeps only what is inside the box';
  String get sectionInset => russian ? 'Размер коробки' : 'Box size';
  String get sectionView => russian ? 'По взгляду' : 'View';
  String get viewFront => russian ? 'Спереди' : 'Front';
  String get viewBack => russian ? 'Сзади' : 'Back';
  String get viewLeft => russian ? 'Слева' : 'Left';
  String get viewRight => russian ? 'Справа' : 'Right';
  String get viewTop => russian ? 'Сверху' : 'Top';
  String get viewBottom => russian ? 'Снизу' : 'Bottom';
  String get cameraViews => russian ? 'Виды' : 'Views';
  String get cameraHome => russian ? 'Камера по умолчанию' : 'Default camera';
  String get walk => russian ? 'По этажу' : 'Walk';
  String get walkStop => russian ? 'Орбита' : 'Orbit';
  String walkHint(String storey, {required bool clear}) {
    final place = clear
        ? (russian ? 'старт вне габаритов' : 'start is outside the boxes')
        : (russian ? 'старт внутри габарита' : 'start is inside a box');
    return russian
        ? '$storey · глаз 1,6 м · $place · сквозь стены'
        : '$storey · eye 1.6 m · $place · through walls';
  }

  String get actions => russian ? 'Действия' : 'Actions';
  String get loadingMesh => russian ? 'Загрузка меша…' : 'Loading mesh…';

  String get closingModel =>
      russian ? 'Освобождение памяти…' : 'Releasing memory…';

  String meshProgress(int loaded, int total) =>
      russian ? 'Сетка $loaded / $total' : 'Meshes $loaded / $total';

  String extracting(int percent) =>
      russian ? 'Распаковка $percent%' : 'Extracting $percent%';

  String meshReady({
    required bool lod0,
    required int elementFiles,
    required int drawn,
    bool partial = false,
    int boxes = 0,
  }) {
    if (partial && !lod0) {
      return russian
          ? 'Сцена: часть модели, GLB элементов: $elementFiles, боксы: $boxes, в кадре: $drawn'
          : 'Scene: partial model, element GLBs: $elementFiles, boxes: $boxes, drawn: $drawn';
    }
    final lod = lod0 ? 'lod0' : (russian ? 'нет lod0' : 'no lod0');
    final boxText = boxes > 0
        ? (russian ? ', боксы: $boxes' : ', boxes: $boxes')
        : '';
    return russian
        ? 'Сцена: $lod, GLB элементов: $elementFiles$boxText, в кадре: $drawn'
        : 'Scene: $lod, element GLBs: $elementFiles$boxText, drawn: $drawn';
  }

  String get converter => russian ? 'Конвертер' : 'Converter';
  String get converterFolder =>
      russian ? 'Каталог с IFC и пакетами' : 'Folder with IFC and packages';
  String get converterProgram =>
      russian ? 'Программа fbvconv' : 'fbvconv program';
  String get convert => russian ? 'Конвертировать' : 'Convert';
  String get converterEmpty => russian
      ? 'В каталоге нет IFC и пакетов'
      : 'No IFC or packages in this folder';
  String get converterLog => russian ? 'Журнал' : 'Log';
  String get converterRunning => russian ? 'Идёт конвертация' : 'Converting';
  String get converterIdle => russian ? 'Не запускалась' : 'Not run';
  String converterDone(int code) => russian
      ? (code == 0 ? 'Готово, код 0' : 'Ошибка, код $code')
      : (code == 0 ? 'Done, code 0' : 'Failed, code $code');
  String get converterExists => russian
      ? 'Каталог результата уже есть. Он не перезаписывается.'
      : 'The output folder already exists. It is not overwritten.';
  String get remarks => russian ? 'Замечания' : 'Remarks';
  String get remarksLocal => russian
      ? 'Хранятся рядом с пакетом, не внутри него. Сеть и сервер здесь не используются. Файл BCF можно унести отдельно.'
      : 'Stored beside the package, not inside it. No network and no server. The BCF file can be carried separately.';
  String get remarkHint => russian ? 'Текст замечания' : 'Remark text';
  String get remarkPhoto =>
      russian ? 'Путь к фото, если есть' : 'Path to a photo, if any';
  String get addRemark => russian ? 'Добавить замечание' : 'Add remark';
  String get showViewpoint => russian ? 'Показать ракурс' : 'Show view';
  String get syncUrl => russian
      ? 'Адрес сервера организации или соседа в сети'
      : 'Organisation server or LAN peer';
  String get syncPull => russian ? 'Забрать' : 'Pull';
  String get syncListen => russian ? 'Слушать' : 'Listen';
  String syncDone(int copied, int kept) => russian
      ? 'Синхронизация: скопировано $copied, оставлено $kept'
      : 'Sync: copied $copied, kept $kept';
  String syncListening(String url) => russian
      ? 'Слушаю $url. Для другого компьютера подставьте адрес этой машины.'
      : 'Listening at $url. Another computer uses this machine\'s address.';
  String get exportBcf => russian ? 'Экспорт BCF' : 'Export BCF';
  String get importBcf => russian ? 'Импорт BCF' : 'Import BCF';
  String get bcfFile => russian ? 'Файл BCF' : 'BCF file';
  String get remarkHasPhoto => russian ? 'Есть фото' : 'Has a photo';
  String get noRemarks =>
      russian ? 'К этому элементу замечаний нет' : 'No remarks on this element';
  String unmatchedRemarks(int count) => russian
      ? 'Без элемента в этом пакете: $count'
      : 'Not matched to an element in this package: $count';

  String get kindIfc => 'IFC';
  String get kindPackage => russian ? 'Пакет' : 'Package';

  String lengthMm(double metres) {
    final mm = metres * 1000.0;
    final text = (mm - mm.round()).abs() < 1e-3
        ? mm.round().toString()
        : mm.toStringAsFixed(1);
    return '$text ${russian ? 'мм' : 'mm'}';
  }
}
