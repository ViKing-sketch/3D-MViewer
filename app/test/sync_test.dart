import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/server_link.dart';
import 'package:field_bim_viewer/src/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  setUp(() {
    HttpOverrides.global = _PassthroughHttp();
  });

  test(
    'loopback pull copies a newer package and keeps a newer remark',
    () async {
      final root = Directory.systemTemp.createTempSync('fbv-sync-');
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final dest = Directory(p.join(root.path, 'dest'))..createSync();
      final pkg = File(p.join(source.path, 'wall.fbvpkg'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      File(
        p.join(source.path, 'wall.fbvpkg.remarks.json'),
      ).writeAsStringSync('{"remarks":[]}');
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

  test('a range returns the tail and a bad range is rejected', () async {
    final root = Directory.systemTemp.createTempSync('fbv-sync-range-');
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final payload = List<int>.generate(10, (i) => i + 3);
    File(p.join(source.path, 'wall.fbvpkg')).writeAsBytesSync(payload);
    final server = await SyncServer.start(source.path);
    final client = HttpClient();
    try {
      final tail = await _ranged(
        client,
        server.base,
        'wall.fbvpkg',
        'bytes=4-',
      );
      expect(tail.status, HttpStatus.partialContent);
      expect(tail.range, 'bytes 4-9/10');
      expect(tail.body, payload.sublist(4));

      final bounded = await _ranged(
        client,
        server.base,
        'wall.fbvpkg',
        'bytes=2-5',
      );
      expect(bounded.status, HttpStatus.partialContent);
      expect(bounded.body, payload.sublist(2, 6));

      final past = await _ranged(
        client,
        server.base,
        'wall.fbvpkg',
        'bytes=40-',
      );
      expect(past.status, HttpStatus.requestedRangeNotSatisfiable);

      final multi = await _ranged(
        client,
        server.base,
        'wall.fbvpkg',
        'bytes=0-1,2-3',
      );
      expect(multi.status, HttpStatus.requestedRangeNotSatisfiable);
    } finally {
      client.close(force: true);
      await server.close();
    }
  });

  test(
    'a dropped pull keeps the local file and the next pull resumes',
    () async {
      final root = Directory.systemTemp.createTempSync('fbv-sync-resume-');
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final dest = Directory(p.join(root.path, 'dest'))..createSync();
      final payload = List<int>.generate(32, (i) => i + 1);
      final pkg = File(p.join(source.path, 'wall.fbvpkg'))
        ..writeAsBytesSync(payload);
      pkg.setLastModifiedSync(DateTime.utc(2026, 11, 24, 12));
      final local = File(p.join(dest.path, 'wall.fbvpkg'))
        ..writeAsBytesSync([9, 9, 9, 9]);
      local.setLastModifiedSync(DateTime.utc(2026, 11, 1));

      final server = await SyncServer.start(source.path);
      try {
        server.responseByteLimit = 5;
        await expectLater(
          pullLibrary(dest.path, server.base),
          throwsA(
            isA<SyncInterrupted>()
                .having((error) => error.got, 'got', 5)
                .having((error) => error.total, 'total', 32)
                .having((error) => error.path, 'path', 'wall.fbvpkg'),
          ),
        );
        expect(local.readAsBytesSync(), [9, 9, 9, 9]);
        expect(syncCatalog(dest.path).files.map((file) => file.path), [
          'wall.fbvpkg',
        ]);
        expect(
          Directory(p.join(dest.path, '.fbv-sync-parts')).existsSync(),
          isTrue,
        );

        server.responseByteLimit = null;
        final done = await pullLibrary(dest.path, server.base);
        expect(done.copied, 1);
        expect(done.kept, 0);
        expect(local.readAsBytesSync(), payload);
        expect(server.requestRanges, contains('bytes=5-'));
        expect(
          Directory(p.join(dest.path, '.fbv-sync-parts')).listSync(),
          isEmpty,
        );

        pkg.writeAsBytesSync(List<int>.filled(16, 7));
        pkg.setLastModifiedSync(DateTime.utc(2026, 11, 24, 18));
        server.responseByteLimit = 4;
        await expectLater(
          pullLibrary(dest.path, server.base),
          throwsA(
            isA<SyncInterrupted>().having((error) => error.got, 'got', 4),
          ),
        );
        expect(local.readAsBytesSync(), payload);
        server.responseByteLimit = null;
        final replaced = await pullLibrary(dest.path, server.base);
        expect(replaced.copied, 1);
        expect(local.readAsBytesSync(), List<int>.filled(16, 7));
      } finally {
        await server.close();
      }
    },
  );

  testWidgets('the library names a stopped pull and the next pull finishes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('fbv-sync-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final dest = Directory(p.join(root.path, 'dest'))..createSync();
    final payload = List<int>.generate(24, (i) => i + 2);
    final pkg = File(p.join(source.path, 'wall.fbvpkg'))
      ..writeAsBytesSync(payload);
    pkg.setLastModifiedSync(DateTime.utc(2026, 11, 24, 12));
    final local = File(p.join(dest.path, 'wall.fbvpkg'))
      ..writeAsBytesSync([1, 2, 3]);
    local.setLastModifiedSync(DateTime.utc(2026, 11, 1));
    final server = await SyncServer.start(source.path);
    server.responseByteLimit = 6;

    await tester.pumpWidget(
      FieldBimApp(initialLibrary: dest.path, tokenStore: MemoryTokenStore()),
    );
    await tester.pump();
    await tester.tap(find.text('Подключиться к серверу организации'));
    await tester.pump();
    await tester.tap(find.text('Дополнительно'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('server-address')),
      server.base.toString(),
    );
    await tester.tap(find.text('Подключить'));
    await _until(tester, find.textContaining('Обрыв'));
    expect(local.readAsBytesSync(), [1, 2, 3]);
    expect(
      find.textContaining('wall.fbvpkg, получено 6 из 24'),
      findsOneWidget,
    );
    expect(find.textContaining('Connection refused'), findsNothing);

    server.responseByteLimit = null;
    await tester.tap(find.text('Повторить'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.textContaining('Обрыв').evaluate().isEmpty &&
          _sameBytes(local.readAsBytesSync(), payload)) {
        break;
      }
    }
    expect(local.readAsBytesSync(), payload);
    expect(server.requestRanges, contains('bytes=6-'));
    await tester.runAsync(server.close);
  });
}

Future<({int status, String? range, List<int> body})> _ranged(
  HttpClient client,
  Uri base,
  String path,
  String range,
) async {
  final request = await client.getUrl(
    base.replace(path: '/fbv-sync/file', queryParameters: {'path': path}),
  );
  request.headers.set(HttpHeaders.rangeHeader, range);
  final response = await request.close();
  final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
  return (
    status: response.statusCode,
    range: response.headers.value(HttpHeaders.contentRangeHeader),
    body: body,
  );
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $finder');
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

class _PassthroughHttp extends HttpOverrides {}
