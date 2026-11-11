import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/filament_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _repoFile(String relative) =>
    p.normalize(p.join(Directory.current.path, '..', relative));

/// Drag the portrait sheet to just under the 0.55 snap and let go.
///
/// The sheet still settles on that snap. The render view stays full size:
/// the inset is not published, so the surface under the sheet is not resized.
Future<void> _releaseJustUnderMidSnap(WidgetTester tester, Finder handle) async {
  final sheet = tester.widget<DraggableScrollableSheet>(
    find.byType(DraggableScrollableSheet),
  );
  final controller = sheet.controller!;
  final viewport = find.byType(FilamentViewport);
  final slot = tester.getSize(viewport);
  expect(slot.height, greaterThan(100));
  expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);

  final parent = tester.getSize(find.byType(DraggableScrollableSheet)).height;
  final dy = -(0.545 - controller.size) * parent;
  final gesture = await tester.startGesture(tester.getCenter(handle));
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);
    expect(tester.getSize(viewport), slot);
  }
  await gesture.up();

  final sizes = <double>[];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    sizes.add(controller.size);
    expect(tester.widget<FilamentViewport>(viewport).bottomInset, 0);
    expect(tester.getSize(viewport), slot);
  }
  final tail = sizes.sublist(sizes.length - 8);
  final hi = tail.reduce((a, b) => a > b ? a : b);
  final lo = tail.reduce((a, b) => a < b ? a : b);
  expect(
    hi - lo,
    lessThan(0.002),
    reason: 'sheet kept moving: sizes=$sizes',
  );
  expect(
    (tail.last - 0.55).abs(),
    lessThan(0.01),
    reason: 'expected the 0.55 snap, sizes=$sizes',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty sheet snaps over a fixed viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FieldBimApp(autoOpenPath: _repoFile('testdata/sample_model')),
    );
    await tester.pump();
    expect(find.text('Выберите элемент'), findsOneWidget);
    await _releaseJustUnderMidSnap(tester, find.text('Выберите элемент'));
  });

  testWidgets('properties sheet snaps over a fixed viewport', (tester) async {
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
    await _releaseJustUnderMidSnap(tester, find.text('Свойства'));
  });
}
