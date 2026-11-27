import 'dart:io';

import 'package:field_bim_viewer/main.dart';
import 'package:field_bim_viewer/src/server_link.dart';
import 'package:field_bim_viewer/src/strings.dart';
import 'package:field_bim_viewer/src/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  setUp(() {
    HttpOverrides.global = _PassthroughHttp();
  });

  test('a connect link round-trips the address and the token', () {
    final link = ServerLink(Uri.parse('http://10.0.0.8:8080'), 'abc-token');
    final again = ServerLink.parse(link.encode());
    expect(again, isNotNull);
    expect(again!.address.toString(), 'http://10.0.0.8:8080');
    expect(again.token, 'abc-token');
    expect(ServerLink.parse('http://10.0.0.8:8080'), isNull);
  });

  test('the token is not written next to the library', () async {
    final root = Directory.systemTemp.createTempSync('fbv-token-');
    addTearDown(() => root.deleteSync(recursive: true));
    const token = 'token-secret-value';
    final store = MemoryTokenStore();
    await store.write(token);
    const SyncSettings(
      serverUrl: 'http://10.0.0.8:8080',
      setup: 'server',
      serverPackages: ['wall.fbvpkg'],
    ).save(root.path);
    final text = SyncSettings.fileIn(root.path).readAsStringSync();
    expect(text.contains(token), isFalse);
    expect(text.contains('token'), isFalse);
    final loaded = SyncSettings.load(root.path);
    expect(loaded.serverUrl, 'http://10.0.0.8:8080');
    expect(loaded.setup, 'server');
    expect(loaded.serverPackages, ['wall.fbvpkg']);
    expect(await store.read(), token);
  });

  test('an old address file is treated as an already chosen server', () {
    final root = Directory.systemTemp.createTempSync('fbv-old-sync-');
    addTearDown(() => root.deleteSync(recursive: true));
    SyncSettings.fileIn(
      root.path,
    ).writeAsStringSync('{"server_url":"http://10.0.0.2:9"}');
    final loaded = SyncSettings.load(root.path);
    expect(loaded.serverUrl, 'http://10.0.0.2:9');
    expect(loaded.setup, 'server');
  });

  test('a refused connection is not shown as the socket text', () {
    final notice = syncNotice(
      const SocketException('Connection refused'),
      const S(true),
    );
    expect(notice.kind, SyncNoticeKind.unavailable);
    expect(notice.message, contains('недоступен'));
    expect(notice.message, isNot(contains('Connection refused')));
    expect(
      syncNotice(const SyncAccessRevoked(), const S(true)).kind,
      SyncNoticeKind.revoked,
    );
  });

  test(
    'a wrong token is rejected and the matching token copies the file',
    () async {
      final root = Directory.systemTemp.createTempSync('fbv-auth-');
      final source = Directory(p.join(root.path, 'source'))..createSync();
      final dest = Directory(p.join(root.path, 'dest'))..createSync();
      File(p.join(source.path, 'wall.fbvpkg')).writeAsBytesSync([1, 2, 3, 4]);
      final server = await SyncServer.start(
        source.path,
        expectedToken: 'secret',
      );
      try {
        await expectLater(
          pullLibrary(dest.path, server.base),
          throwsA(isA<SyncAccessRevoked>()),
        );
        expect(File(p.join(dest.path, 'wall.fbvpkg')).existsSync(), isFalse);
        final done = await pullLibrary(dest.path, server.base, token: 'secret');
        expect(done.copied, 1);
        expect(done.packages, ['wall.fbvpkg']);
        expect(File(p.join(dest.path, 'wall.fbvpkg')).readAsBytesSync(), [
          1,
          2,
          3,
          4,
        ]);
      } finally {
        await server.close();
      }
    },
  );

  testWidgets('the file path does not mention a server', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('fbv-local-ui-');
    addTearDown(() => root.deleteSync(recursive: true));

    await tester.pumpWidget(FieldBimApp(initialLibrary: root.path));
    await tester.pump();
    expect(find.text('Открыть файл на устройстве'), findsOneWidget);
    expect(find.text('Подключиться к серверу организации'), findsOneWidget);

    await tester.tap(find.text('Открыть файл на устройстве'));
    await tester.pump();
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n')
        .toLowerCase();
    expect(texts.contains('сервер'), isFalse);
    expect(texts.contains('порт'), isFalse);
    expect(texts.contains('server'), isFalse);
    expect(texts.contains('port'), isFalse);
    expect(find.text('Пакетов не найдено'), findsOneWidget);
  });

  test('a directory package is copied and named', () async {
    final root = Directory.systemTemp.createTempSync('fbv-dir-pull-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final dest = Directory(p.join(root.path, 'dest'))..createSync();
    final sample = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    final copied = Process.runSync('cp', [
      '-a',
      sample,
      p.join(source.path, 'sample_model'),
    ]);
    expect(copied.exitCode, 0, reason: copied.stderr.toString());
    final server = await SyncServer.start(source.path, expectedToken: 'secret');
    try {
      final done = await pullLibrary(dest.path, server.base, token: 'secret');
      expect(done.packages, ['sample_model']);
      expect(
        File(p.join(dest.path, 'sample_model', 'manifest.json')).existsSync(),
        isTrue,
      );
    } finally {
      await server.close();
    }
  });

  testWidgets('a connect link pulls a package and marks it', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = Directory.systemTemp.createTempSync('fbv-link-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final dest = Directory(p.join(root.path, 'dest'))..createSync();
    final sample = p.normalize(
      p.join(Directory.current.path, '..', 'testdata', 'sample_model'),
    );
    final copied = Process.runSync('cp', [
      '-a',
      sample,
      p.join(source.path, 'sample_model'),
    ]);
    expect(copied.exitCode, 0, reason: copied.stderr.toString());
    final server = await SyncServer.start(source.path, expectedToken: 'secret');
    final link = ServerLink(server.base, 'secret').encode();

    await tester.pumpWidget(
      FieldBimApp(
        initialLibrary: dest.path,
        initialConnectLink: link,
        tokenStore: MemoryTokenStore(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 160; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byIcon(Icons.cloud_outlined).evaluate().isNotEmpty &&
          find.text('Sample Project').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Sample Project'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.textContaining('Connection refused'), findsNothing);
    final saved = SyncSettings.fileIn(dest.path).readAsStringSync();
    expect(saved.contains('secret'), isFalse);
    expect(saved.contains('sample_model'), isTrue);
    await tester.runAsync(server.close);
  });
}

class _PassthroughHttp extends HttpOverrides {}
