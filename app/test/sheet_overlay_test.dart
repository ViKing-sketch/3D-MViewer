import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/filament_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _repoFile(String relative) =>
    p.normalize(p.join(Directory.current.path, '..', relative));

/// Drag the portrait sheet up and check the render slot does not follow it.
Future<void> _swipeSheetOverFixedView(
  WidgetTester tester,
  Finder handle,
) async {
  final sheet = tester.widget<DraggableScrollableSheet>(
    find.byType(DraggableScrollableSheet),
  );
  final controller = sheet.controller!;
  final openedAt = controller.size;
  final viewport = find.byType(FilamentViewport);
  final slot = tester.getSize(viewport);
  expect(slot.height, greaterThan(100));
  expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);

  final parent = tester.getSize(find.byType(DraggableScrollableSheet)).height;
  final dy = -(0.60 - controller.size) * parent;
  final gesture = await tester.startGesture(tester.getCenter(handle));
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);
    expect(tester.getSize(viewport), slot);
  }
  await gesture.up();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);
    expect(tester.getSize(viewport), slot);
  }
  expect(
    controller.size,
    greaterThan(openedAt + 0.2),
    reason: 'sheet did not open over the view: size=${controller.size}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty sheet overlays a fixed viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FieldBimApp(autoOpenPath: _repoFile('testdata/sample_model')),
    );
    await tester.pump();
    expect(find.text('Выберите элемент'), findsOneWidget);
    await _swipeSheetOverFixedView(tester, find.text('Выберите элемент'));
  });

  testWidgets('properties sheet overlays a fixed viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FieldBimApp(autoOpenPath: _repoFile('testdata/sample_model')),
    );
    await tester.pump();
    await tester.tap(find.text('Дерево'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wall W-1'));
    await tester.pump();
    await tester.tap(find.text('3D'));
    await tester.pumpAndSettle();
    expect(find.text('Свойства'), findsOneWidget);
    await _swipeSheetOverFixedView(tester, find.text('Свойства'));
  });
}
