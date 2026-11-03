import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:field_bim_viewer/src/package_session.dart';
import 'package:field_bim_viewer/src/sqlite_setup.dart';
import 'package:field_bim_viewer/src/text_bytes.dart';
import 'package:field_bim_viewer/src/zip_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('session reads quantities from the sample package', () async {
    final path = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    final session = PackageSession.openPath(path);
    final elements = session.elements();
    final wall = elements.firstWhere((element) => element.name == 'Wall W-1');
    final quantities = session.quantities(wall.id);
    expect(quantities.map((q) => q.name), contains('Length'));
    final length = quantities.firstWhere((q) => q.name == 'Length');
    expect(length.value, closeTo(5, 1e-6));
    expect(length.unit, 'm');
    expect(length.kind, 'Length');
    final zip = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_wall.fbvpkg'),
    );
    final zipped = PackageSession.openPath(zip);
    expect(zipped.summary.name, 'Sample Project');
    expect(zipped.elements().map((e) => e.name), contains('Slab S-1'));
    zipped.close();
    zipped.close();
    session.close();
    session.close();
  });

  test('cancelling an extract completes', () async {
    final zip = File(
      p.normalize(
        p.join(Directory.current.path, '..', 'testdata', 'sample_wall.fbvpkg'),
      ),
    );
    final dest = await Directory.systemTemp.createTemp('fbv-cancel-');
    try {
      await expectLater(
        ZipStore.extractAsync(zip, dest, onCancel: (cancel) => cancel()),
        throwsA(isA<ZipStoreException>()),
      );
    } finally {
      if (dest.existsSync()) dest.deleteSync(recursive: true);
    }
  });

  test('a continuation byte in sqlite text is kept', () {
    final raw = Uint8List(54);
    for (var i = 0; i < 53; i++) {
      raw[i] = 0x41;
    }
    raw[53] = 0xA0;
    expect(decodePackageBytes(raw), '${'A' * 53}\u00A0');
    expect(decodePackageBytes(utf8.encode('Марка')), 'Марка');

    final source = Directory(
      p.normalize(
        p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
      ),
    );
    final temp = Directory.systemTemp.createTempSync('fbv-text-');
    addTearDown(() => temp.deleteSync(recursive: true));
    _copyTree(source, temp);
    configureSqlite();
    final db = sqlite3.open(p.join(temp.path, 'meta.sqlite'));
    final hex = raw
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    db.execute(
      "UPDATE elements SET name = CAST(x'$hex' AS TEXT) WHERE name = 'Wall W-1'",
    );
    db.dispose();
    final meta = File(p.join(temp.path, 'meta.sqlite')).readAsBytesSync();
    final manifestFile = File(p.join(temp.path, 'manifest.json'));
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final parts = manifest['parts'] as Map<String, dynamic>;
    final metaPart = parts['meta.sqlite'] as Map<String, dynamic>;
    metaPart['sha256'] = sha256.convert(meta).toString();
    metaPart['bytes'] = meta.length;
    manifestFile.writeAsStringSync(jsonEncode(manifest));

    final session = PackageSession.openPath(temp.path);
    addTearDown(session.close);
    final wall = session.elements().firstWhere(
      (element) => element.ifcClass == 'IfcWall',
    );
    expect(wall.name, '${'A' * 53}\u00A0');
  });

  test('zip open runs off the caller and keeps the sample names', () async {
    final zip = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_wall.fbvpkg'),
    );
    var ticks = 0;
    final session = await PackageSession.openPathAsync(
      zip,
      onProgress: (_, _) => ticks++,
    );
    expect(ticks, greaterThan(0));
    expect(session.summary.name, 'Sample Project');
    expect(
      session.elements().map((element) => element.name),
      contains('Slab S-1'),
    );
    session.close();
  });
}

void _copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(followLinks: false)) {
    final target = p.join(to.path, p.basename(entity.path));
    if (entity is Directory) {
      _copyTree(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}
