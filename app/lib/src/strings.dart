class S {
  const S(this.russian);
  final bool russian;

  String get appTitle => 'Field BIM Viewer';
  String get library => russian ? 'Модели' : 'Models';
  String get scan => russian ? 'Сканировать' : 'Scan';
  String get openSample => russian ? 'Открыть образец' : 'Open sample';
  String get pathHint => russian ? 'Каталог с пакетами' : 'Folder with packages';
  String get emptyLibrary => russian ? 'Пакетов не найдено' : 'No packages found';
  String get properties => russian ? 'Свойства' : 'Properties';
  String get specification => russian ? 'Спецификация' : 'Specification';
  String get searchHint => russian ? 'Имя, марка, GlobalId' : 'Name, tag, GlobalId';
  String get renderStub => russian
      ? '3D-рендер Filament работает на Android. Здесь доступны дерево, свойства и спецификация.'
      : 'The Filament renderer runs on Android. The tree, properties and specification are available here.';
  String get about => russian ? 'О программе' : 'About';
  String get delete => russian ? 'Удалить' : 'Delete';
  String get deleteConfirm => russian ? 'Удалить пакет с устройства?' : 'Delete this package from the device?';
  String get cancel => russian ? 'Отмена' : 'Cancel';
  String get exportCsv => russian ? 'Экспорт CSV' : 'Export CSV';
  String get theme => russian ? 'Тема' : 'Theme';
  String get language => russian ? 'Язык' : 'Language';
  String get offline =>
      russian ? 'Офлайн. Сеть приложению не нужна.' : 'Offline. This app does not use the network.';
  String get allClasses => russian ? 'Все классы' : 'All classes';
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
  String get importFailed => russian ? 'Не удалось импортировать пакет' : 'Could not import the package';
  String get libraryStored => russian
      ? 'Пакеты хранятся в памяти приложения. Общая папка Android недоступна.'
      : 'Packages are kept in app storage. Android shared storage cannot be read directly.';
  String get fitAll => russian ? 'Вписать всё' : 'Fit all';
  String get fitSelected => russian ? 'Вписать выбранное' : 'Fit selected';
  String get hide => russian ? 'Скрыть' : 'Hide';
  String get showAll => russian ? 'Показать всё' : 'Show all';
  String get isolate => russian ? 'Изолировать' : 'Isolate';
  String get xray => russian ? 'Рентген' : 'X-ray';
  String get viewFront => russian ? 'Спереди' : 'Front';
  String get viewBack => russian ? 'Сзади' : 'Back';
  String get viewLeft => russian ? 'Слева' : 'Left';
  String get viewRight => russian ? 'Справа' : 'Right';
  String get viewTop => russian ? 'Сверху' : 'Top';
  String get viewBottom => russian ? 'Снизу' : 'Bottom';
  String get loadingMesh => russian ? 'Загрузка меша…' : 'Loading mesh…';

  String meshReady(bool lod0, int elementFiles, int drawn) {
    final lod = lod0 ? 'lod0' : (russian ? 'нет lod0' : 'no lod0');
    return russian
        ? 'Сцена: $lod, GLB элементов: $elementFiles, в кадре: $drawn'
        : 'Scene: $lod, element GLBs: $elementFiles, drawn: $drawn';
  }

  String lengthMm(double metres) {
    final mm = metres * 1000.0;
    final text = (mm - mm.round()).abs() < 1e-3 ? mm.round().toString() : mm.toStringAsFixed(1);
    return '$text ${russian ? 'мм' : 'mm'}';
  }
}
