import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:field_bim_viewer/src/zip_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('sample package lists and extracts without holding the archive', () {
    final zip = File(p.normalize(p.join(Directory.current.path, '..', 'testdata', 'sample_wall.fbvpkg')));
    final names = ZipStore.list(zip).map((entry) => entry.name).toList();
    expect(names, contains('manifest.json'));
    expect(names, contains('mesh/lod0.glb'));
    expect(names, contains('meta.sqlite'));
    final dest = Directory.systemTemp.createTempSync('fbv-zip-');
    addTearDown(() => dest.deleteSync(recursive: true));
    final hashes = ZipStore.extract(zip, dest);
    expect(File(p.join(dest.path, 'mesh', 'lod0.glb')).lengthSync(), 5644);
    expect(hashes['manifest.json'], sha256.convert(File(p.join(dest.path, 'manifest.json')).readAsBytesSync()).toString());
    final sessionHashes = ZipStore.extract(zip, Directory.systemTemp.createTempSync('fbv-zip2-'), only: const {
      'manifest.json',
      'meta.sqlite',
    });
    expect(sessionHashes.keys, containsAll(['manifest.json', 'meta.sqlite']));
    expect(sessionHashes.containsKey('mesh/lod0.glb'), isFalse);
  });

  test('store entries larger than one chunk round-trip', () {
    final payload = Uint8List(ZipStore.chunkSize + 100);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = i & 0xff;
    }
    final zip = File(p.join(Directory.systemTemp.path, 'fbv-chunk-${DateTime.now().microsecondsSinceEpoch}.zip'));
    zip.writeAsBytesSync(_storeZip({'mesh/blob.bin': payload}));
    addTearDown(zip.deleteSync);
    final dest = Directory.systemTemp.createTempSync('fbv-chunk-out-');
    addTearDown(() => dest.deleteSync(recursive: true));
    final hashes = ZipStore.extract(zip, dest);
    final out = File(p.join(dest.path, 'mesh', 'blob.bin'));
    expect(out.lengthSync(), payload.length);
    expect(hashes['mesh/blob.bin'], sha256.convert(payload).toString());
  });

  test('parent segments in zip names are rejected', () {
    final zip = File(p.join(Directory.systemTemp.path, 'fbv-slip-${DateTime.now().microsecondsSinceEpoch}.zip'));
    zip.writeAsBytesSync(_storeZip({'../escape.txt': Uint8List.fromList([1, 2, 3])}, allowUnsafe: true));
    addTearDown(zip.deleteSync);
    expect(() => ZipStore.list(zip), throwsA(isA<ZipStoreException>()));
  });
}

Uint8List _storeZip(Map<String, Uint8List> files, {bool allowUnsafe = false}) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  for (final entry in files.entries) {
    final name = Uint8List.fromList(entry.key.codeUnits);
    final data = entry.value;
    final offset = local.length;
    _u32(local, 0x04034b50);
    _u16(local, 20);
    _u16(local, 0);
    _u16(local, 0);
    _u16(local, 0);
    _u16(local, 0);
    _u32(local, 0);
    _u32(local, data.length);
    _u32(local, data.length);
    _u16(local, name.length);
    _u16(local, 0);
    local.add(name);
    local.add(data);
    _u32(central, 0x02014b50);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, data.length);
    _u32(central, data.length);
    _u16(central, name.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, offset);
    central.add(name);
    if (!allowUnsafe && entry.key.contains('..')) {
      fail('test tried to build an unsafe name without allowUnsafe');
    }
  }
  final cdOffset = local.length;
  final cd = central.toBytes();
  final out = BytesBuilder();
  out.add(local.toBytes());
  out.add(cd);
  _u32(out, 0x06054b50);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, files.length);
  _u16(out, files.length);
  _u32(out, cd.length);
  _u32(out, cdOffset);
  _u16(out, 0);
  return out.toBytes();
}

void _u16(BytesBuilder out, int value) {
  out.addByte(value & 0xff);
  out.addByte((value >> 8) & 0xff);
}

void _u32(BytesBuilder out, int value) {
  out.addByte(value & 0xff);
  out.addByte((value >> 8) & 0xff);
  out.addByte((value >> 16) & 0xff);
  out.addByte((value >> 24) & 0xff);
}
