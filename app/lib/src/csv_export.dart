import 'dart:io';

import 'package:path/path.dart' as p;

class CsvSaveException implements Exception {
  CsvSaveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A single file name. Path separators and other odd characters are removed.
String csvFileName(String modelName) {
  final cleaned = modelName
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final stem = cleaned.isEmpty ? 'spec' : cleaned;
  if (stem.toLowerCase().endsWith('.csv')) return stem;
  return '$stem.csv';
}

/// Writes [csv] into [directory]. The directory must already exist.
File writeSpecCsv({
  required String directory,
  required String modelName,
  required String csv,
}) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw CsvSaveException('Папка не найдена: $directory');
  }
  final file = File(p.join(dir.path, csvFileName(modelName)));
  file.writeAsStringSync(csv);
  return file;
}
