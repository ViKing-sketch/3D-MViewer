import 'dart:io';

import 'package:field_bim_viewer/src/csv_export.dart';
import 'package:field_bim_viewer/src/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('csv file name keeps the model name and refuses a missing folder', () {
    expect(csvFileName('Sample Project'), 'Sample Project.csv');
    expect(csvFileName(r'a/b:c'), 'a_b_c.csv');
    expect(csvFileName(''), 'spec.csv');
    expect(
      () => writeSpecCsv(
        directory: p.join(Directory.systemTemp.path, 'fbv-missing-csv-dir'),
        modelName: 'Sample',
        csv: 'a\n',
      ),
      throwsA(isA<CsvSaveException>()),
    );
  });

  test('writeSpecCsv puts the text in the chosen folder', () {
    final dir = Directory.systemTemp.createTempSync('fbv-csv-unit-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final csv = specCsv([
      SpecRow(
        storeyName: 'Level 1',
        ifcClass: 'IfcWall',
        typeName: 'W',
        material: 'Бетон',
        elementCount: 1,
        quantityKind: '',
        quantitySum: null,
      ),
    ]);
    final file = writeSpecCsv(
      directory: dir.path,
      modelName: 'Sample Project',
      csv: csv,
    );
    expect(file.parent.path, dir.path);
    expect(file.readAsStringSync(), contains('IfcWall'));
    expect(file.path.contains('fbv-spec-'), isFalse);
  });
}
