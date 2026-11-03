import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A ZIP reader for format_version 1 packages.
///
/// Packages are STORE (method 0) and are not ZIP64. Entries are copied in
/// fixed-size chunks so a multi-hundred-megabyte `.fbvpkg` is never decoded
/// into one Dart buffer.
class ZipStoreException implements Exception {
  ZipStoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZipEntryInfo {
  ZipEntryInfo({
    required this.name,
    required this.method,
    required this.size,
    required this.localOffset,
  });

  final String name;
  final int method;
  final int size;
  final int localOffset;

  bool get isDirectory => name.endsWith('/');
}

class ZipStore {
  static const int chunkSize = 1024 * 1024;

  static List<ZipEntryInfo> list(File zip) {
    final raf = zip.openSync();
    try {
      return _centralDirectory(raf);
    } finally {
      raf.closeSync();
    }
  }

  /// Extracts [only] the named entries, or every file when [only] is null.
  ///
  /// Returns the SHA-256 hex of each extracted file. Directory entries are
  /// skipped. Names that escape [dest] are rejected.
  static Map<String, String> extract(
    File zip,
    Directory dest, {
    Set<String>? only,
  }) {
    final raf = zip.openSync();
    final hashes = <String, String>{};
    try {
      for (final entry in _centralDirectory(raf)) {
        if (entry.isDirectory) continue;
        if (only != null && !only.contains(entry.name)) continue;
        if (entry.method != 0) {
          throw ZipStoreException('ZIP entry ${entry.name} is not STORE');
        }
        final out = _safeFile(dest, entry.name);
        out.parent.createSync(recursive: true);
        hashes[entry.name] = _copyEntry(raf, entry, out);
      }
      if (only != null) {
        for (final name in only) {
          if (!hashes.containsKey(name)) {
            throw ZipStoreException('В архиве нет $name');
          }
        }
      }
      return hashes;
    } finally {
      raf.closeSync();
    }
  }

  static String hashFile(File file) {
    final raf = file.openSync();
    try {
      final sink = _OneDigest();
      final input = sha256.startChunkedConversion(sink);
      final chunk = Uint8List(chunkSize);
      while (true) {
        final read = raf.readIntoSync(chunk);
        if (read <= 0) break;
        input.add(read == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, read));
      }
      input.close();
      final digest = sink.digest;
      if (digest == null) throw ZipStoreException('Пустой хэш ${file.path}');
      return digest.toString();
    } finally {
      raf.closeSync();
    }
  }

  static List<ZipEntryInfo> _centralDirectory(RandomAccessFile raf) {
    final length = raf.lengthSync();
    if (length < 22) throw ZipStoreException('Файл слишком мал для ZIP');
    final tailSize = length < 22 + 65535 ? length : 22 + 65535;
    raf.setPositionSync(length - tailSize);
    final tail = raf.readSync(tailSize);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] != 0x50 || tail[i + 1] != 0x4b || tail[i + 2] != 0x05 || tail[i + 3] != 0x06) {
        continue;
      }
      final commentLen = _u16(tail, i + 20);
      if (i + 22 + commentLen == tail.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ZipStoreException('В файле нет каталога ZIP');
    final entries = _u16(tail, eocd + 10);
    final cdSize = _u32(tail, eocd + 12);
    final cdOffset = _u32(tail, eocd + 16);
    if (entries == 0xffff || cdOffset == 0xffffffff || cdSize == 0xffffffff) {
      throw ZipStoreException('ZIP64 не поддерживается');
    }
    if (cdOffset + cdSize > length) throw ZipStoreException('Каталог ZIP выходит за файл');
    raf.setPositionSync(cdOffset);
    final central = raf.readSync(cdSize);
    if (central.length != cdSize) throw ZipStoreException('Каталог ZIP прочитан не полностью');
    final found = <ZipEntryInfo>[];
    var offset = 0;
    while (offset + 46 <= central.length) {
      final sig = _u32(central, offset);
      if (sig != 0x02014b50) throw ZipStoreException('Повреждена запись каталога ZIP');
      final method = _u16(central, offset + 10);
      final size = _u32(central, offset + 24);
      final nameLen = _u16(central, offset + 28);
      final extraLen = _u16(central, offset + 30);
      final commentLen = _u16(central, offset + 32);
      final local = _u32(central, offset + 42);
      final nameStart = offset + 46;
      final nameEnd = nameStart + nameLen;
      if (nameEnd > central.length) throw ZipStoreException('Имя ZIP выходит за каталог');
      final name = String.fromCharCodes(central.sublist(nameStart, nameEnd));
      _rejectName(name);
      found.add(ZipEntryInfo(name: name, method: method, size: size, localOffset: local));
      offset = nameEnd + extraLen + commentLen;
      if (offset > central.length) throw ZipStoreException('Каталог ZIP оборван');
    }
    if (found.length != entries && entries != 0) {
      // Some writers leave the count as the number of records; trust the walk
      // when it consumed the directory. A short walk is a corrupt archive.
      if (offset != central.length) throw ZipStoreException('Каталог ZIP оборван');
    }
    return found;
  }

  static String _copyEntry(RandomAccessFile raf, ZipEntryInfo entry, File out) {
    raf.setPositionSync(entry.localOffset);
    final header = raf.readSync(30);
    if (header.length != 30 || _u32(header, 0) != 0x04034b50) {
      throw ZipStoreException('Нет локального заголовка ${entry.name}');
    }
    final nameLen = _u16(header, 26);
    final extraLen = _u16(header, 28);
    raf.setPositionSync(raf.positionSync() + nameLen + extraLen);
    final sink = out.openSync(mode: FileMode.write);
    final hashSink = _OneDigest();
    final input = sha256.startChunkedConversion(hashSink);
    try {
      var left = entry.size;
      while (left > 0) {
        final n = left < chunkSize ? left : chunkSize;
        final bytes = raf.readSync(n);
        if (bytes.length != n) throw ZipStoreException('Обрыв данных ${entry.name}');
        sink.writeFromSync(bytes);
        input.add(bytes);
        left -= n;
      }
    } finally {
      sink.closeSync();
    }
    input.close();
    final digest = hashSink.digest;
    if (digest == null) throw ZipStoreException('Пустой хэш ${entry.name}');
    return digest.toString();
  }

  static File _safeFile(Directory dest, String name) {
    _rejectName(name);
    final parts = name.split('/').where((part) => part.isNotEmpty).toList();
    final file = File(p.joinAll([dest.path, ...parts]));
    final root = p.normalize(dest.path);
    final target = p.normalize(file.path);
    if (target != root && !p.isWithin(root, target)) {
      throw ZipStoreException('Недопустимое имя в архиве: $name');
    }
    return file;
  }

  static void _rejectName(String name) {
    if (name.isEmpty || name.startsWith('/') || name.startsWith('\\') || name.contains('\\')) {
      throw ZipStoreException('Недопустимое имя в архиве: $name');
    }
    if (name.split('/').contains('..')) {
      throw ZipStoreException('Недопустимое имя в архиве: $name');
    }
  }

  static int _u16(List<int> bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);

  static int _u32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

class _OneDigest implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}
