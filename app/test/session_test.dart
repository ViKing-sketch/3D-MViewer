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

  test('format_version 1 opens and reports no systems', () {
    final path = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    final session = PackageSession.openPath(path);
    expect(session.formatVersion, 1);
    expect(session.systems(), isEmpty);
    expect(session.tiles(), isEmpty);
    final wall = session.elements().firstWhere(
      (element) => element.name == 'Wall W-1',
    );
    expect(wall.systemIds, isEmpty);
    session.close();
  });

  test('an unknown format_version is rejected with the number', () {
    final copy = _copySample();
    try {
      final manifest = _readManifest(copy);
      manifest['format_version'] = 4;
      _writeManifest(copy, manifest);
      expect(
        () => PackageSession.openPath(copy.path),
        throwsA(
          isA<PackageException>().having(
            (error) => error.message,
            'message',
            contains('Неподдерживаемая format_version: 4'),
          ),
        ),
      );
    } finally {
      copy.deleteSync(recursive: true);
    }
  });

  test('format_version 2 without the system tables fails explicitly', () {
    final copy = _copySample();
    try {
      final manifest = _readManifest(copy);
      manifest['format_version'] = 2;
      _writeManifest(copy, manifest);
      expect(
        () => PackageSession.openPath(copy.path),
        throwsA(
          isA<PackageException>().having(
            (error) => error.message,
            'message',
            contains('schema_meta format_version не совпал'),
          ),
        ),
      );

      configureSqlite();
      final db = sqlite3.open(p.join(copy.path, 'meta.sqlite'));
      db.execute(
        "UPDATE schema_meta SET value = '2' WHERE key = 'format_version'",
      );
      db.dispose();
      final bumped = _readManifest(copy);
      _refreshPart(copy, bumped, 'meta.sqlite');
      _writeManifest(copy, bumped);
      expect(
        () => PackageSession.openPath(copy.path),
        throwsA(
          isA<PackageException>().having(
            (error) => error.message,
            'message',
            contains('нет таблицы systems'),
          ),
        ),
      );
    } finally {
      copy.deleteSync(recursive: true);
    }
  });

  test('format_version 2 keeps membership and still opens a member', () {
    final copy = _copySample();
    try {
      _installHeating(copy);
      final session = PackageSession.openPath(copy.path);
      expect(session.formatVersion, 2);
      expect(session.systems().map((system) => system.name), ['Heating']);
      final elements = session.elements();
      final wall = elements.firstWhere((element) => element.name == 'Wall W-1');
      final column = elements.firstWhere(
        (element) => element.name == 'Column C-1',
      );
      expect(wall.systemIds, [1]);
      expect(column.systemIds, isEmpty);
      expect(session.tiles(), isEmpty);
      session.close();
    } finally {
      copy.deleteSync(recursive: true);
    }
  });

  test('format_version 3 reads one tile per element', () {
    final copy = _copySample();
    try {
      _installTiles(copy);
      final session = PackageSession.openPath(copy.path);
      expect(session.formatVersion, 3);
      final tiles = session.tiles();
      expect(tiles, hasLength(2));
      final architecture = tiles.firstWhere((tile) => tile.discipline == 'architecture');
      expect(architecture.elementIds, [1]);
      expect(architecture.storeyId, isNotNull);
      final none = tiles.firstWhere((tile) => tile.discipline.isEmpty);
      expect(none.elementIds, [4]);
      final ids = tiles.expand((tile) => tile.elementIds).toList()..sort();
      expect(ids, [1, 4]);
      session.close();
    } finally {
      copy.deleteSync(recursive: true);
    }
  });
}

Directory _copySample() {
  final source = Directory(
    p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    ),
  );
  final dest = Directory.systemTemp.createTempSync('fbv-ver-');
  _copyTree(source, dest);
  return dest;
}

Map<String, dynamic> _readManifest(Directory root) {
  return jsonDecode(File(p.join(root.path, 'manifest.json')).readAsStringSync())
      as Map<String, dynamic>;
}

void _writeManifest(Directory root, Map<String, dynamic> manifest) {
  File(
    p.join(root.path, 'manifest.json'),
  ).writeAsStringSync(jsonEncode(manifest));
}

void _refreshPart(Directory root, Map<String, dynamic> manifest, String part) {
  final file = File(p.join(root.path, part));
  final bytes = file.readAsBytesSync();
  final parts = manifest['parts'] as Map<String, dynamic>;
  final meta = Map<String, dynamic>.from(parts[part] as Map);
  meta['sha256'] = sha256.convert(bytes).toString();
  meta['bytes'] = bytes.length;
  parts[part] = meta;
}

void _installHeating(Directory root) {
  configureSqlite();
  final db = sqlite3.open(p.join(root.path, 'meta.sqlite'));
  db.execute("UPDATE schema_meta SET value = '2' WHERE key = 'format_version'");
  db.execute('''
CREATE TABLE systems(
  id INTEGER PRIMARY KEY,
  guid TEXT,
  ifc_class TEXT NOT NULL,
  name TEXT,
  description TEXT
)''');
  db.execute('''
CREATE TABLE system_elements(
  system_id INTEGER NOT NULL,
  element_id INTEGER NOT NULL,
  PRIMARY KEY (system_id, element_id)
)''');
  db.execute(
    "INSERT INTO systems(id, guid, ifc_class, name, description) "
    "VALUES (1, '0Yvh4\$d\$H4PgX8k1\$f\$xS4', 'IfcDistributionSystem', 'Heating', '')",
  );
  db.execute(
    'INSERT INTO system_elements(system_id, element_id) VALUES (1, 1)',
  );
  db.dispose();
  final manifest = _readManifest(root);
  manifest['format_version'] = 2;
  _refreshPart(root, manifest, 'meta.sqlite');
  _writeManifest(root, manifest);
}

void _installTiles(Directory root) {
  _installHeating(root);
  configureSqlite();
  final db = sqlite3.open(p.join(root.path, 'meta.sqlite'));
  db.execute("UPDATE schema_meta SET value = '3' WHERE key = 'format_version'");
  db.execute('''
CREATE TABLE tiles(
  id INTEGER PRIMARY KEY,
  storey_id INTEGER,
  discipline TEXT NOT NULL,
  element_count INTEGER NOT NULL
)''');
  db.execute('''
CREATE TABLE tile_elements(
  tile_id INTEGER NOT NULL,
  element_id INTEGER NOT NULL,
  PRIMARY KEY (tile_id, element_id)
)''');
  final storey = db.select(
    "SELECT storey_id FROM elements WHERE name = 'Wall W-1'",
  );
  final storeyId = storey.first.columnAt(0) as int;
  db.execute(
    'INSERT INTO tiles(id, storey_id, discipline, element_count) VALUES (1, $storeyId, \'architecture\', 1)',
  );
  db.execute(
    'INSERT INTO tiles(id, storey_id, discipline, element_count) VALUES (2, $storeyId, \'\', 1)',
  );
  db.execute('INSERT INTO tile_elements(tile_id, element_id) VALUES (1, 1)');
  db.execute('INSERT INTO tile_elements(tile_id, element_id) VALUES (2, 4)');
  db.dispose();
  final manifest = _readManifest(root);
  manifest['format_version'] = 3;
  _refreshPart(root, manifest, 'meta.sqlite');
  _writeManifest(root, manifest);
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
