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
      ? '3D-рендер Filament будет подключён отдельным шагом. Сейчас доступны дерево, свойства и спецификация.'
      : 'The Filament viewport is planned as a separate step. The tree, properties and specification are available.';
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

  String lengthMm(double metres) {
    final mm = metres * 1000.0;
    final text = (mm - mm.round()).abs() < 1e-3 ? mm.round().toString() : mm.toStringAsFixed(1);
    return '$text ${russian ? 'мм' : 'mm'}';
  }
}
