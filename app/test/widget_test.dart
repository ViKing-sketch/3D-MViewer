import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/model_page.dart';
import 'package:field_bim_viewer/src/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _repoFile(String relative) =>
    p.normalize(p.join(Directory.current.path, '..', relative));

IconButton _tool(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

Future<void> pumpFor(WidgetTester tester, Finder finder) async {
  // Zip open copies on a background isolate. pump() only advances the fake
  // clock, so give that isolate real time and then rebuild.
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    // Elapse the fake clock so a post-extract yield can resume.
    await tester.pump(const Duration(milliseconds: 16));
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
    expect(
      csv.split('\n').first,
      'storey,class,type,material,count,quantity_kind,quantity_sum',
    );
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
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join(' | '),
    );
    expect(find.text('КСИ'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
      'W-1',
    );
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
    await pumpFor(tester, find.text('Sample Project'));
    expect(find.text('Sample Project'), findsWidgets);
    if (find.text('Slab S-1').evaluate().isEmpty) {
      await tester.tap(find.text('Дерево'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
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

  testWidgets('back from a model returns to the previous page', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ModelPage(path: sample, strings: const S(true)),
                  ),
                );
              },
              child: const Text('open-model'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Wall W-1'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump();
    expect(find.text('open-model'), findsOneWidget);
    expect(find.text('Wall W-1'), findsNothing);
  });

  testWidgets('phone portrait separates the tree and the properties sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    expect(find.text('3D'), findsOneWidget);
    expect(find.text('Дерево'), findsOneWidget);
    expect(find.text('Выберите элемент'), findsOneWidget);
    expect(find.byTooltip('Меню'), findsOneWidget);
    expect(find.byTooltip('Рентген'), findsOneWidget);
    expect(_tool(tester, 'Рентген').onPressed, isNull);
    expect(find.byTooltip('Срез'), findsOneWidget);
    expect(find.byTooltip('Изолировать'), findsOneWidget);
    expect(_tool(tester, 'Изолировать').onPressed, isNull);
    expect(find.byTooltip('Камера по умолчанию'), findsOneWidget);
    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    expect(find.text('Показать всё'), findsOneWidget);
    await tester.tap(find.text('Показать всё'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    expect(find.text('Wall W-1'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
    );
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context?.widget is EditableText,
      isFalse,
    );
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Wall W-1'));
    await tester.tap(find.text('Wall W-1'));
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('Свойства'), findsOneWidget);
    expect(find.text('Wall W-1'), findsWidgets);
    expect(_tool(tester, 'Рентген').onPressed, isNotNull);
    expect(_tool(tester, 'Изолировать').onPressed, isNotNull);
    expect(find.text('IfcWall'), findsOneWidget);
    await tester.drag(find.text('Свойства'), const Offset(0, -420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Марка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone landscape keeps properties beside the view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    expect(find.text('3D'), findsOneWidget);
    expect(find.text('Выберите элемент'), findsOneWidget);
    await tester.tap(find.text('Дерево'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Wall W-1'), findsOneWidget);
    await tester.enterText(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
      'Column',
    );
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
    );
    expect(field.controller?.text, 'Column');
    expect(find.text('Column C-1'), findsOneWidget);
    expect(find.text('Wall W-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('section hint explains the clip in both languages', () {
    expect(const S(true).section, 'Срез');
    expect(const S(true).sectionHint, contains('не зависит от зума'));
    expect(const S(false).section, 'Section');
    expect(const S(false).sectionHint, contains('zoom'));
  });

  testWidgets('section mode shows the clipping hint', (tester) async {
    // Landscape under 1100px uses the icon rail, which is short enough that
    // the section control is built. The wide text bar lazily skips it.
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    final toggle = find.byKey(const ValueKey('section-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byTooltip(const S(true).section), findsOneWidget);
    expect(find.textContaining('не зависит от зума'), findsNothing);
    expect(find.byKey(const ValueKey('section-offset')), findsOneWidget);
    expect(find.byKey(const ValueKey('section-flip')), findsOneWidget);
    expect(find.text('По взгляду'), findsOneWidget);
    expect(find.byKey(const ValueKey('section-near')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('section-more')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('section-near')), findsOneWidget);
    expect(find.text('Коробка'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.byKey(const ValueKey('section-inset')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape parks the section strip on the side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('section-toggle')));
    await tester.pump();
    final slider = find.byKey(const ValueKey('section-offset'));
    expect(slider, findsOneWidget);
    final width = tester.getSize(slider).width;
    expect(width, lessThan(220));
    expect(tester.getTopLeft(slider).dx, greaterThan(240));
    final label = tester.renderObject<RenderParagraph>(find.text('По взгляду'));
    expect(
      label.size.width + 1,
      greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('storey and material filters hide the other elements', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('storey-4')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('storey-4')));
    await tester.pump();
    expect(find.text('Wall W-1'), findsWidgets);
    expect(find.text('Column C-1'), findsWidgets);

    final materialStrip = find.ancestor(
      of: find.text('Все материалы'),
      matching: find.byType(Scrollable),
    );
    await tester.drag(materialStrip, const Offset(-420, 0));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('material-Бетон')));
    await tester.pump();
    expect(find.text('Wall W-1'), findsWidgets);
    expect(find.text('Column C-1'), findsNothing);
    expect(find.text('Slab S-1'), findsNothing);
    expect(find.text('Marker no geom'), findsNothing);

    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(_tool(tester, 'Фильтр').isSelected, isTrue);
    await tester.tap(find.byTooltip('Фильтр'));
    await tester.pumpAndSettle();
    expect(find.text('Этаж, класс, материал'), findsOneWidget);
    final sheetStrips = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );
    await tester.drag(sheetStrips.last, const Offset(-420, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('material-Бетон')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать всё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    expect(find.text('Column C-1'), findsOneWidget);
    expect(find.text('Slab S-1'), findsOneWidget);
    expect(find.text('Marker no geom'), findsOneWidget);
    final storeyAll = tester.widget<FilterChip>(
      find.byKey(const ValueKey('storey-all')),
    );
    expect(storeyAll.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a property value search selects that element', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
      'НС-12',
    );
    await tester.pump();
    expect(find.text('Wall W-1'), findsWidgets);
    expect(find.text('Column C-1'), findsNothing);
    expect(find.text('Slab S-1'), findsNothing);
    expect(find.text('Marker no geom'), findsNothing);

    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('Выберите элемент'), findsNothing);
    expect(find.text('Wall W-1'), findsWidgets);

    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Показать всё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    expect(find.text('Column C-1'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.decoration?.hintText == const S(true).searchHint;
      }),
    );
    expect(field.controller?.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('walk mode stands on the storey and orbit leaves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = _repoFile('testdata/sample_model');
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    final toggle = find.byKey(const ValueKey('walk-toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byKey(const ValueKey('walk-hint')), findsOneWidget);
    expect(find.textContaining('Level 1'), findsWidgets);
    expect(find.textContaining('глаз 1,6 м'), findsOneWidget);
    expect(find.textContaining('сквозь стены'), findsOneWidget);
    expect(find.textContaining('старт вне габаритов'), findsOneWidget);
    await tester.tap(find.byTooltip(const S(true).actions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(const S(true).fitAll));
    await tester.pump();
    expect(find.byKey(const ValueKey('walk-hint')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
