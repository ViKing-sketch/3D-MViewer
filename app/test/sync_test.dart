import 'dart:io';

import 'package:field_bim_viewer/src/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'loopback pull copies a newer package and keeps a newer remark',
    () async {
      final root = Directory.systemTemp.createTempSync('fbv-sync-');
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final dest = Directory(p.join(root.path, 'dest'))..createSync();
      final pkg = File(p.join(source.path, 'wall.fbvpkg'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      final remark = File(p.join(source.path, 'wall.fbvpkg.remarks.json'))
        ..writeAsStringSync('{"remarks":[]}');
      File(p.join(source.path, 'notes.txt')).writeAsStringSync('not a package');
      final secret = File(p.join(root.path, 'secret.bin'))
        ..writeAsBytesSync([9, 9]);

      final server = await SyncServer.start(source.path);
      try {
        final first = await pullLibrary(dest.path, server.base);
        expect(first.copied, 2);
        expect(File(p.join(dest.path, 'wall.fbvpkg')).readAsBytesSync(), [
          1,
          2,
          3,
          4,
        ]);
        expect(File(p.join(dest.path, 'notes.txt')).existsSync(), isFalse);
        expect(secret.existsSync(), isTrue);

        final localRemark = File(p.join(dest.path, 'wall.fbvpkg.remarks.json'));
        localRemark.writeAsStringSync('{"remarks":["local"]}');
        final newer = DateTime.now().toUtc().add(const Duration(minutes: 5));
        localRemark.setLastModifiedSync(newer);
        pkg.writeAsBytesSync([5, 6, 7]);
        pkg.setLastModifiedSync(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );

        final second = await pullLibrary(dest.path, server.base);
        expect(second.copied, 1);
        expect(second.kept, 1);
        expect(File(p.join(dest.path, 'wall.fbvpkg')).readAsBytesSync(), [
          5,
          6,
          7,
        ]);
        expect(localRemark.readAsStringSync(), '{"remarks":["local"]}');

        final client = HttpClient();
        final blocked = await client.getUrl(
          server.base.replace(
            path: '/fbv-sync/file',
            queryParameters: {'path': '../secret.bin'},
          ),
        );
        final response = await blocked.close();
        expect(response.statusCode, 404);
        client.close(force: true);
      } finally {
        await server.close();
      }
    },
  );

  test('the server address is a setting beside the library', () {
    final root = Directory.systemTemp.createTempSync('fbv-sync-set-');
    const settings = SyncSettings(serverUrl: 'http://10.0.0.8:8080');
    settings.save(root.path);
    expect(SyncSettings.load(root.path).serverUrl, 'http://10.0.0.8:8080');
    expect(syncCatalog(root.path).files, isEmpty);
    expect(syncPathAllowed('../x'), isFalse);
    expect(syncPathAllowed('a/../b'), isFalse);
  });
}
