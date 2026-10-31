import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _repoFile(String relative) => p.normalize(p.join(Directory.current.path, '..', relative));

Future<void> pumpFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('spec csv escapes commas', () {
    final csv = specCsv([
      SpecRow(
        storeyName: 'Level 1',
        ifcClass: 'IfcWall',
        typeName: 'Basic, Wall',
        material: 'Бетон',
        elementCount: 1,
        quantityKind: '',
        quantitySum: null,
      ),
    ]);
    expect(csv, contains('"Basic, Wall"'));
    expect(csv.split('\n').first, 'storey,class,type,material,count,quantity_kind,quantity_sum');
  });

  testWidgets('directory package shows the property tree', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();

    expect(find.text('Wall W-1'), findsOneWidget);
    expect(find.text('Column C-1'), findsOneWidget);
    expect(find.text('Marker no geom'), findsOneWidget);
    expect(find.textContaining('Filament'), findsOneWidget);

    await tester.tap(find.text('Wall W-1').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Марка'), findsOneWidget);
    expect(find.text('НС-12'), findsOneWidget);
    expect(find.text('да'), findsWidgets);
    expect(
      find.text('5000 мм'),
      findsOneWidget,
      reason: tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | '),
    );
    expect(find.text('КСИ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'W-1');
    await tester.pump();
    expect(find.text('Wall W-1'), findsWidgets);
    expect(find.text('Column C-1'), findsNothing);

    await tester.tap(find.text('Спецификация'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('IfcWall'), findsWidgets);
  });

  testWidgets('zip package opens the same project', (tester) async {
    final zip = _repoFile('testdata/sample_wall.fbvpkg');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: zip));
    await pumpFor(tester, find.text('Slab S-1'));
    expect(find.text('Sample Project'), findsWidgets);
    expect(find.text('Slab S-1'), findsOneWidget);
  });

  testWidgets('library lists a package and can delete a copy', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = Directory(_repoFile('testdata/sample_model'));
    final library = Directory.systemTemp.createTempSync('fbv-lib-');
    final copy = Directory(p.join(library.path, 'copy_model'));
    final copied = Process.runSync('cp', ['-a', source.path, copy.path]);
    expect(copied.exitCode, 0, reason: copied.stderr.toString());

    await tester.pumpWidget(FieldBimApp(initialLibrary: library.path));
    await pumpFor(tester, find.text('Sample Project'));
    expect(find.text('Sample Project'), findsOneWidget);

    await tester.tap(find.byTooltip('Удалить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Пакетов не найдено'), findsOneWidget);
    expect(copy.existsSync(), isFalse);
  });
}
