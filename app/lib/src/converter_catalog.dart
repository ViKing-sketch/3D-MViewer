import 'dart:io';

import 'package:path/path.dart' as p;

enum CatalogKind { ifc, package }

class CatalogEntry {
  const CatalogEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modifiedUtc,
    required this.kind,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modifiedUtc;
  final CatalogKind kind;
}

/// Files and already-built packages in one folder.
///
/// An IFC is a file ending in `.ifc`. A package is a `.fbvpkg` file or a
/// directory that contains `manifest.json`. Other files are skipped.
List<CatalogEntry> listConverterFolder(String folder) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return const [];
  final out = <CatalogEntry>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is File) {
      final lower = p.basename(entity.path).toLowerCase();
      final ifc = lower.endsWith('.ifc');
      final pkg = lower.endsWith('.fbvpkg');
      if (!ifc && !pkg) continue;
      final stat = entity.statSync();
      out.add(
        CatalogEntry(
          path: entity.path,
          name: p.basename(entity.path),
          bytes: stat.size,
          modifiedUtc: stat.modified.toUtc(),
          kind: ifc ? CatalogKind.ifc : CatalogKind.package,
        ),
      );
    } else if (entity is Directory) {
      if (!File(p.join(entity.path, 'manifest.json')).existsSync()) continue;
      out.add(
        CatalogEntry(
          path: entity.path,
          name: p.basename(entity.path),
          bytes: _directoryBytes(entity),
          modifiedUtc: entity.statSync().modified.toUtc(),
          kind: CatalogKind.package,
        ),
      );
    }
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

int _directoryBytes(Directory dir) {
  var total = 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) total += entity.lengthSync();
  }
  return total;
}

/// Directory package written next to the IFC. Not a ZIP.
String outputDirectoryFor(String ifcPath) {
  return p.join(
    p.dirname(ifcPath),
    '${p.basenameWithoutExtension(ifcPath)}.fbv',
  );
}

/// `FBV_PROGRESS <done> <total>` from fbvconv. [total] is a stage count,
/// not a count of elements.
class StageProgress {
  const StageProgress(this.done, this.total);

  final int done;
  final int total;

  double get fraction => done / total;
}

StageProgress? parseStageProgress(String line) {
  final match = RegExp(r'^FBV_PROGRESS (\d+) (\d+)$').firstMatch(line.trim());
  if (match == null) return null;
  final done = int.parse(match.group(1)!);
  final total = int.parse(match.group(2)!);
  if (total <= 0 || done < 0 || done > total) return null;
  return StageProgress(done, total);
}

/// Arguments for one conversion. Analytic mesher, directory package.
List<String> converterArguments(String input, String output) {
  return [input, '-o', output, '--directory', '--mesher', 'analytic'];
}
