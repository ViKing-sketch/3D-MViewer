import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/model.dart';
import 'package:field_bim_viewer/src/remarks.dart';
import 'package:field_bim_viewer/src/remarks_section.dart';
import 'package:field_bim_viewer/src/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

ElementInfo _wall() {
  return ElementInfo(
    id: 7,
    parentId: 0,
    storeyId: 1,
    ifcClass: 'IfcWall',
    name: 'Wall W-1',
    tag: '',
    typeName: '',
    material: '',
    guid: 'WALLGUID0000000000001',
  );
}

void main() {
  test(
    'a remark and its photo round-trip through BCF without entering the package',
    () {
      final root = Directory.systemTemp.createTempSync('fbv-remark-');
      final package = Directory(p.join(root.path, 'model'))..createSync();
      File(p.join(package.path, 'manifest.json')).writeAsStringSync('{}');
      final photo = File(p.join(root.path, 'shot.bin'))
        ..writeAsBytesSync([1, 2, 3, 9]);
      final clock = DateTime.utc(2026, 11, 9, 12);
      final store = RemarkStore(
        package.path,
        now: () => clock,
        ids: RemarkIds(),
      );
      store.add(
        elementId: 7,
        guid: 'WALLGUID0000000000001',
        text: 'трещина <1 & 2>',
        photoSource: photo.path,
      );
      expect(
        File(p.join(package.path, 'manifest.json')).readAsStringSync(),
        '{}',
      );
      expect(Directory(package.path).listSync().length, 1);
      expect(File('${package.path}.remarks.json').existsSync(), isTrue);
      expect(
        store.forElement(7, 'WALLGUID0000000000001').single.text,
        'трещина <1 & 2>',
      );

      final bcf = p.join(root.path, 'notes.bcf');
      store.exportBcf(bcf);
      final other = RemarkStore(
        p.join(root.path, 'other'),
        now: () => clock,
        ids: RemarkIds(),
      );
      final missed = other.importBcf(bcf, {'WALLGUID0000000000001': 7});
      expect(missed, 0);
      final back = other.forElement(7, 'WALLGUID0000000000001').single;
      expect(back.text, 'трещина <1 & 2>');
      expect(back.createdUtc, '2026-11-09T12:00:00.000Z');
      expect(other.photoFile(back)!.readAsBytesSync(), [1, 2, 3, 9]);

      final lost = other.importBcf(bcf, const {});
      expect(lost, 0, reason: 'the same topic is not imported twice');
    },
  );

  test('a topic with an unknown GlobalId is kept and counted', () {
    final root = Directory.systemTemp.createTempSync('fbv-remark-miss-');
    final store = RemarkStore(p.join(root.path, 'model'), ids: RemarkIds());
    store.add(elementId: 1, guid: 'KNOWN', text: 'keep');
    final bcf = p.join(root.path, 'one.bcf');
    store.exportBcf(bcf);
    final imported = RemarkStore(p.join(root.path, 'empty'), ids: RemarkIds());
    expect(imported.importBcf(bcf, const {}), 1);
    expect(imported.remarks.single.elementId, isNull);
    expect(imported.remarks.single.guid, 'KNOWN');
    expect(imported.forElement(1, 'KNOWN').single.text, 'keep');
    expect(imported.forElement(2, 'OTHER'), isEmpty);
  });

  testWidgets('the remark form writes a sidecar and the open model shows it', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('fbv-remark-ui-');
    final store = RemarkStore(p.join(root.path, 'model'), ids: RemarkIds());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemarksSection(
            strings: const S(true),
            store: store,
            element: _wall(),
            guidToElement: const {'WALLGUID0000000000001': 7},
            onChanged: () {},
          ),
        ),
      ),
    );
    expect(find.text('К этому элементу замечаний нет'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('remark-text')), 'шов');
    await tester.tap(find.text('Добавить замечание'));
    await tester.pump();
    expect(find.text('шов'), findsOneWidget);
    expect(store.remarks.single.guid, 'WALLGUID0000000000001');

    final bcf = p.join(root.path, 'out.bcf');
    await tester.tap(find.text('Экспорт BCF'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bcf-path')), bcf);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(File(bcf).existsSync(), isTrue);
  });

  testWidgets('an open package shows the remarks section', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sample = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    await tester.pumpWidget(FieldBimApp(autoOpenPath: sample));
    await tester.pump();
    await tester.tap(find.text('Wall W-1').first);
    await tester.pump();
    expect(find.text('Марка'), findsOneWidget);
    await tester.drag(find.text('Марка'), const Offset(0, -900));
    await tester.pump();
    await tester.drag(find.text('Марка'), const Offset(0, -900));
    await tester.pump();
    expect(find.text('Замечания'), findsOneWidget);
    expect(find.textContaining('не внутри него'), findsOneWidget);
  });
}
