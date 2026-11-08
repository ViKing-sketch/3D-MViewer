import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'fts_query.dart';
import 'model.dart';
import 'sqlite_setup.dart';
import 'text_bytes.dart';
import 'zip_store.dart';

class PackageException implements Exception {
  PackageException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PackageSession {
  PackageSession._(
    this.summary,
    this._db,
    this._temp,
    this.manifest,
    this.rootPath,
  );

  final PackageSummary summary;
  final Database _db;
  final Directory? _temp;
  final Map<String, dynamic> manifest;

  /// Directory that contains `manifest.json` and `mesh/`. For a zip package this
  /// is the streamed extract, not the archive itself.
  final String rootPath;

  static PackageSession openPath(String path) {
    configureSqlite();
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      return _openDirectory(path, deleteOnClose: null, isZip: false);
    }
    if (entity == FileSystemEntityType.file) {
      final temp = Directory.systemTemp.createTempSync('fbvpkg-');
      try {
        final hashes = ZipStore.extract(File(path), temp);
        return _openDirectory(
          temp.path,
          deleteOnClose: temp,
          isZip: true,
          displayPath: path,
          hashes: hashes,
        );
      } on ZipStoreException catch (error) {
        temp.deleteSync(recursive: true);
        throw PackageException(error.message);
      } catch (_) {
        temp.deleteSync(recursive: true);
        rethrow;
      }
    }
    throw PackageException('Путь не найден: $path');
  }

  /// Zip packages are unpacked on a background isolate. A directory is opened
  /// on the caller, same as [openPath].
  static Future<PackageSession> openPathAsync(
    String path, {
    void Function(int done, int total)? onProgress,
    void Function(void Function() cancel)? onCancel,
    bool Function()? isCancelled,
  }) async {
    configureSqlite();
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.directory) {
      return _openDirectory(path, deleteOnClose: null, isZip: false);
    }
    if (entity == FileSystemEntityType.file) {
      final temp = Directory.systemTemp.createTempSync('fbvpkg-');
      try {
        final hashes = await ZipStore.extractAsync(
          File(path),
          temp,
          onProgress: onProgress,
          onCancel: onCancel,
        );
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() == true) {
          throw PackageException('cancelled');
        }
        final session = _openDirectory(
          temp.path,
          deleteOnClose: temp,
          isZip: true,
          displayPath: path,
          hashes: hashes,
        );
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() == true) {
          session.close();
          throw PackageException('cancelled');
        }
        return session;
      } on ZipStoreException catch (error) {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
        throw PackageException(error.message);
      } catch (_) {
        if (temp.existsSync()) temp.deleteSync(recursive: true);
        rethrow;
      }
    }
    throw PackageException('Путь не найден: $path');
  }

  static PackageSession _openDirectory(
    String directory, {
    required Directory? deleteOnClose,
    required bool isZip,
    String? displayPath,
    bool verifyParts = true,
    Map<String, String>? hashes,
  }) {
    final root = Directory(directory);
    final manifestFile = File(p.join(root.path, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw PackageException('В пакете нет manifest.json');
    }
    final manifest =
        jsonDecode(decodePackageBytes(manifestFile.readAsBytesSync()))
            as Map<String, dynamic>;
    final version = manifest['format_version'];
    if (version != 1) {
      throw PackageException('Неподдерживаемая format_version: $version');
    }
    if (verifyParts) _verifyParts(root, manifest, hashes);
    final db = sqlite3.open(
      p.join(root.path, 'meta.sqlite'),
      mode: OpenMode.readOnly,
    );
    final count =
        db.select('SELECT COUNT(*) AS n FROM elements').first['n'] as int;
    final source = (manifest['source'] as Map?) ?? const {};
    final bytes = _partBytes(manifest);
    return PackageSession._(
      PackageSummary(
        path: displayPath ?? root.path,
        name:
            (manifest['name'] as String?) ??
            p.basename(displayPath ?? root.path),
        schema: (source['schema'] as String?) ?? '',
        elementCount: count,
        bytes: bytes,
        isZip: isZip,
      ),
      db,
      deleteOnClose,
      manifest,
      root.path,
    );
  }

  static void _verifyParts(
    Directory root,
    Map<String, dynamic> manifest,
    Map<String, String>? hashes,
  ) {
    final parts = manifest['parts'];
    if (parts is! Map) throw PackageException('manifest.parts отсутствует');
    for (final entry in parts.entries) {
      final name = entry.key.toString().replaceAll('\\', '/');
      final file = File(p.joinAll([root.path, ...name.split('/')]));
      if (!file.existsSync()) {
        throw PackageException('Нет части пакета ${entry.key}');
      }
      final meta = entry.value;
      if (meta is! Map) continue;
      final expected = meta['sha256']?.toString() ?? '';
      if (expected.isEmpty) continue;
      final actual = hashes?[name] ?? ZipStore.hashFile(file);
      if (actual != expected) {
        throw PackageException('Хэш не совпал: ${entry.key}');
      }
    }
  }

  static int _partBytes(Map<String, dynamic> manifest) {
    final parts = manifest['parts'];
    if (parts is! Map) return 0;
    var sum = 0;
    for (final value in parts.values) {
      if (value is Map && value['bytes'] is num) {
        sum += (value['bytes'] as num).toInt();
      }
    }
    return sum;
  }

  List<SpatialNode> spatial() {
    final rows = _db.select(
      'SELECT id, parent_id, CAST(kind AS BLOB), CAST(COALESCE(name, \'\') AS BLOB), elevation FROM spatial ORDER BY id',
    );
    return [
      for (final row in rows)
        SpatialNode(
          id: row.columnAt(0) as int,
          parentId: row.columnAt(1) as int? ?? 0,
          kind: packageText(row.columnAt(2)),
          name: packageText(row.columnAt(3)),
          hasElevation: row.columnAt(4) != null,
          elevation: (row.columnAt(4) as num?)?.toDouble() ?? 0,
        ),
    ];
  }

  /// Element ids whose FTS row matches [query].
  ///
  /// The index covers name, tag, GlobalId, type name, and property text.
  /// An empty query returns no ids; the caller treats that as "no search".
  /// A MATCH the tokenizer rejects also returns no ids.
  List<int> searchIds(String query) {
    final match = ftsMatchExpression(query);
    if (match == null) return const [];
    try {
      final rows = _db.select(
        'SELECT element_id FROM fts_elements WHERE fts_elements MATCH ?1 ORDER BY element_id',
        [match],
      );
      return [for (final row in rows) row.columnAt(0) as int];
    } on SqliteException {
      return const [];
    }
  }

  List<ElementInfo> elements() {
    final rows = _db.select('''
SELECT e.id, COALESCE(e.parent_id, 0), COALESCE(e.storey_id, 0), CAST(e.ifc_class AS BLOB),
       CAST(COALESCE(e.name, '') AS BLOB), CAST(COALESCE(e.tag, '') AS BLOB),
       CAST(COALESCE(t.name, '') AS BLOB),
       CAST(COALESCE((SELECT m.name FROM material_layers ml
                 JOIN materials m ON m.id = ml.material_id
                 WHERE ml.set_id = e.material_set_id
                 ORDER BY ml.layer_order LIMIT 1), '') AS BLOB),
       CAST(e.guid AS BLOB)
FROM elements e
LEFT JOIN types t ON t.id = e.type_id
ORDER BY e.id
''');
    return [
      for (final row in rows)
        ElementInfo(
          id: row.columnAt(0) as int,
          parentId: row.columnAt(1) as int,
          storeyId: row.columnAt(2) as int,
          ifcClass: packageText(row.columnAt(3)),
          name: packageText(row.columnAt(4)),
          tag: packageText(row.columnAt(5)),
          typeName: packageText(row.columnAt(6)),
          material: packageText(row.columnAt(7)),
          guid: packageText(row.columnAt(8)),
        ),
    ];
  }

  List<PropInfo> props(int elementId) {
    final rows = _db.select(
      '''
SELECT CAST(p.name AS BLOB), CAST(pr.name AS BLOB), CAST(COALESCE(pr.value_text, '') AS BLOB), CAST(p.source AS BLOB)
FROM psets p
JOIN props pr ON pr.pset_id = p.id
WHERE p.element_id = ?1
   OR p.type_id = (SELECT type_id FROM elements WHERE id = ?1)
ORDER BY p.id, pr.id
''',
      [elementId],
    );
    return [
      for (final row in rows)
        PropInfo(
          pset: packageText(row.columnAt(0)),
          name: packageText(row.columnAt(1)),
          valueText: packageText(row.columnAt(2)),
          source: packageText(row.columnAt(3)),
        ),
    ];
  }

  List<QuantityInfo> quantities(int elementId) {
    final rows = _db.select(
      '''
SELECT CAST(COALESCE(qset, '') AS BLOB), CAST(name AS BLOB), CAST(kind AS BLOB), CAST(COALESCE(unit, '') AS BLOB), value
FROM quantities WHERE element_id = ? ORDER BY id
''',
      [elementId],
    );
    return [
      for (final row in rows)
        QuantityInfo(
          qset: packageText(row.columnAt(0)),
          name: packageText(row.columnAt(1)),
          kind: packageText(row.columnAt(2)),
          unit: packageText(row.columnAt(3)),
          value: (row.columnAt(4) as num).toDouble(),
        ),
    ];
  }

  List<ClassInfo> classes(int elementId) {
    final rows = _db.select(
      '''
SELECT CAST(COALESCE(system, '') AS BLOB), CAST(COALESCE(code, '') AS BLOB), CAST(COALESCE(title, '') AS BLOB)
FROM classification WHERE element_id = ? ORDER BY id
''',
      [elementId],
    );
    return [
      for (final row in rows)
        ClassInfo(
          system: packageText(row.columnAt(0)),
          code: packageText(row.columnAt(1)),
          title: packageText(row.columnAt(2)),
        ),
    ];
  }

  List<SpecRow> specifications() {
    final rows = _db.select('''
SELECT CAST(COALESCE(sp.name, '') AS BLOB), CAST(COALESCE(s.ifc_class, '') AS BLOB),
       CAST(COALESCE(s.type_name, '') AS BLOB), CAST(COALESCE(s.material_name, '') AS BLOB),
       s.element_count, CAST(s.quantity_kind AS BLOB), s.quantity_sum
FROM spec_views s
LEFT JOIN spatial sp ON sp.id = s.storey_id
ORDER BY s.id
''');
    return [
      for (final row in rows)
        SpecRow(
          storeyName: packageText(row.columnAt(0)),
          ifcClass: packageText(row.columnAt(1)),
          typeName: packageText(row.columnAt(2)),
          material: packageText(row.columnAt(3)),
          elementCount: row.columnAt(4) as int,
          quantityKind: packageText(row.columnAt(5)),
          quantitySum: (row.columnAt(6) as num?)?.toDouble(),
        ),
    ];
  }

  var _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _db.dispose();
    final temp = _temp;
    if (temp != null && temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  }
}

List<PackageSummary> scanLibrary(String directory) {
  configureSqlite();
  final root = Directory(directory);
  if (!root.existsSync()) return const [];
  final found = <PackageSummary>[];
  for (final entity in root.listSync(followLinks: false)) {
    if (entity is Directory &&
        File(p.join(entity.path, 'manifest.json')).existsSync()) {
      try {
        final session = PackageSession._openDirectory(
          entity.path,
          deleteOnClose: null,
          isZip: false,
          verifyParts: false,
        );
        found.add(session.summary);
        session.close();
      } on PackageException {
        continue;
      }
    } else if (entity is File &&
        entity.path.toLowerCase().endsWith('.fbvpkg')) {
      Directory? temp;
      try {
        temp = Directory.systemTemp.createTempSync('fbvscan-');
        // Listing a library must not unpack meshes. Integrity is checked on open.
        ZipStore.extract(
          entity,
          temp,
          only: const {'manifest.json', 'meta.sqlite'},
        );
        final session = PackageSession._openDirectory(
          temp.path,
          deleteOnClose: temp,
          isZip: true,
          displayPath: entity.path,
          verifyParts: false,
        );
        found.add(session.summary);
        session.close();
        temp = null;
      } catch (_) {
        temp?.deleteSync(recursive: true);
      }
    }
  }
  found.sort((a, b) => a.name.compareTo(b.name));
  return found;
}

void deletePackage(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.directory) {
    Directory(path).deleteSync(recursive: true);
  } else if (type == FileSystemEntityType.file) {
    File(path).deleteSync();
  }
}
