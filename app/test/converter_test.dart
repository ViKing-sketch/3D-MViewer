import 'dart:io';

import 'package:field_bim_viewer/src/converter_catalog.dart';
import 'package:field_bim_viewer/src/converter_page.dart';
import 'package:field_bim_viewer/src/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('folder list keeps IFC and packages and skips other files', () {
    final root = Directory.systemTemp.createTempSync('fbv-catalog-');
    File(p.join(root.path, 'wall.ifc')).writeAsStringSync('ISO-10303-21;');
    File(p.join(root.path, 'notes.txt')).writeAsStringSync('skip');
    File(p.join(root.path, 'done.fbvpkg')).writeAsBytesSync([1, 2, 3, 4]);
    final pkg = Directory(p.join(root.path, 'dir-pkg'))..createSync();
    File(p.join(pkg.path, 'manifest.json')).writeAsStringSync('{}');
    File(p.join(pkg.path, 'meta.sqlite')).writeAsBytesSync(List.filled(10, 7));
    final empty = Directory(p.join(root.path, 'not-a-package'))..createSync();
    File(p.join(empty.path, 'readme.txt')).writeAsStringSync('no');

    final entries = listConverterFolder(root.path);
    expect(entries.map((e) => e.name), ['dir-pkg', 'done.fbvpkg', 'wall.ifc']);
    expect(entries[0].kind, CatalogKind.package);
    expect(entries[0].bytes, 12);
    expect(entries[1].bytes, 4);
    expect(entries[2].kind, CatalogKind.ifc);
    expect(converterArguments('/in/wall.ifc', '/out/wall.fbv'), [
      '/in/wall.ifc',
      '-o',
      '/out/wall.fbv',
      '--directory',
      '--mesher',
      'analytic',
    ]);
    expect(
      outputDirectoryFor('/in/wall.ifc'),
      '/out/wall.fbv'.replaceFirst('/out', '/in'),
    );
  });

  testWidgets('convert runs fbvconv and shows the log', (tester) async {
    final root = Directory.systemTemp.createTempSync('fbv-conv-ui-');
    File(p.join(root.path, 'wall.ifc')).writeAsStringSync('ISO-10303-21;');
    final program = File(p.join(root.path, 'fake-fbvconv'))
      ..writeAsStringSync('''#!/bin/sh
mkdir -p "\$3"
echo converted "\$1" > "\$3/marker.txt"
echo converted "\$1"
exit 0
''');
    Process.runSync('chmod', ['+x', program.path]);

    await tester.pumpWidget(
      MaterialApp(
        home: ConverterPage(
          strings: const S(true),
          initialDirectory: root.path,
          initialProgram: program.path,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('wall.ifc'), findsOneWidget);
    expect(find.textContaining('IFC ·'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Конвертировать'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.textContaining('converted').evaluate().isNotEmpty &&
            find.textContaining('Готово, код 0').evaluate().isNotEmpty) {
          break;
        }
      }
    });
    expect(find.textContaining('converted'), findsOneWidget);
    expect(find.textContaining('Готово, код 0'), findsOneWidget);
    expect(
      File(p.join(root.path, 'wall.fbv', 'marker.txt')).readAsStringSync(),
      contains('wall.ifc'),
    );

    await tester.tap(find.text('Конвертировать'));
    await tester.pump();
    expect(find.textContaining('не перезаписывается'), findsOneWidget);
  });
}
