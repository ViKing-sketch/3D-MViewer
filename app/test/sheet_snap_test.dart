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
/// The snap then moves the sheet by less than the old 0.015 inset gate.
/// That leftover strip of the SurfaceView is what flashed black.
Future<void> _releaseJustUnderMidSnap(WidgetTester tester, Finder handle) async {
  final sheet = tester.widget<DraggableScrollableSheet>(
    find.byType(DraggableScrollableSheet),
  );
  final controller = sheet.controller!;
  final parent = tester.getSize(find.byType(DraggableScrollableSheet)).height;
  final dy = -(0.545 - controller.size) * parent;
  final gesture = await tester.startGesture(tester.getCenter(handle));
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();

  final sizes = <double>[];
  final insets = <double>[];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    sizes.add(controller.size);
    insets.add(
      tester
          .widget<FilamentViewport>(find.byType(FilamentViewport))
          .bottomInset,
    );
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
  final expected = tail.last.clamp(0.0, 0.72);
  expect(
    (insets.last - expected).abs(),
    lessThan(1 / parent),
    reason:
        'camera inset ${insets.last} left a gap under sheet $expected. '
        'insets=$insets',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty sheet inset follows the snap', (tester) async {
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

  testWidgets('properties sheet inset follows the snap', (tester) async {
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
