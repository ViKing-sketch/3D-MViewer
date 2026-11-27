import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:field_bim_viewer/src/sync.dart';
import 'package:qr/qr.dart';

/// Same text `ServerLink.encode` builds in `lib/src/server_link.dart`.
String connectLink(Uri address, String token) {
  return Uri(
    scheme: 'fbv',
    host: 'connect',
    queryParameters: {'url': address.toString(), 'token': token},
  ).toString();
}

void main(List<String> args) async {
  String? rootArg;
  var port = 8080;
  String? token;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'dart run tool/lan_sync_server.dart [--root каталог] [--port 8080] [--token секрет]',
      );
      return;
    }
    if (arg == '--root' && i + 1 < args.length) {
      rootArg = args[++i];
    } else if (arg == '--port' && i + 1 < args.length) {
      port = int.parse(args[++i]);
    } else if (arg == '--token' && i + 1 < args.length) {
      token = args[++i];
    } else {
      stderr.writeln('Неизвестный аргумент: $arg');
      exitCode = 64;
      return;
    }
  }

  final root = _root(rootArg);
  final catalog = syncCatalog(root.path);
  if (catalog.files.isEmpty) {
    stderr.writeln('В каталоге нет тестовых пакетов: ${root.path}');
    exitCode = 1;
    return;
  }
  token ??= _token();
  final SyncServer server;
  try {
    server = await SyncServer.start(
      root.path,
      address: InternetAddress.anyIPv4,
      port: port,
      expectedToken: token,
    );
  } on SocketException catch (error) {
    stderr.writeln('Порт $port занят или недоступен ($error).');
    stderr.writeln('Запустите снова с другим портом: --port ${port + 1}');
    exitCode = 1;
    return;
  }

  final ips = await _lanIps();
  final chosen = _prefer(ips);
  stdout.writeln('Сервер fbv-sync-1 слушает 0.0.0.0:$port');
  stdout.writeln('Каталог: ${root.path}');
  stdout.writeln('Файлов в обмене: ${catalog.files.length}');
  stdout.writeln('Токен: $token');
  if (chosen == null) {
    stdout.writeln(
      'IPv4 в локальной сети не найден. Выполните ipconfig и возьмите адрес Wi-Fi.',
    );
  } else {
    final base = Uri.parse('http://$chosen:$port');
    final link = connectLink(base, token);
    final page = File('sync-link.html');
    page.writeAsStringSync(
      _html(link: link, address: base, token: token, ips: ips),
    );
    stdout.writeln('Адрес для телефона: $base');
    stdout.writeln('Ссылка: $link');
    stdout.writeln('QR: ${page.absolute.path}');
    if (ips.length > 1) {
      stdout.writeln('Другие адреса этой машины:');
      for (final ip in ips) {
        if (ip != chosen) stdout.writeln('  http://$ip:$port');
      }
    }
  }
  stdout.writeln('Окно не закрывать. Остановка: Ctrl+C.');
  stdout.writeln(
    'Если Windows спросит доступ для dart.exe, разрешите частные сети.',
  );
  await _untilStopped();
  await server.close();
}

Future<void> _untilStopped() {
  final done = Completer<void>();
  void finish() {
    if (!done.isCompleted) done.complete();
  }

  ProcessSignal.sigint.watch().listen((_) => finish());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => finish());
  }
  return done.future;
}

Directory _root(String? arg) {
  if (arg != null && arg.isNotEmpty) return Directory(arg);
  for (final candidate in ['testdata/public', '../testdata/public']) {
    final dir = Directory(candidate);
    if (dir.existsSync()) return dir;
  }
  return Directory('../testdata/public');
}

String _token() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<List<String>> _lanIps() async {
  final found = <String>[];
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (address.isLoopback) continue;
        if (address.address.startsWith('169.254.')) continue;
        found.add(address.address);
      }
    }
  } catch (_) {}
  return found;
}

String? _prefer(List<String> ips) {
  bool match(String ip, bool Function(String ip) test) => test(ip);
  for (final test in [_is192, _is10, _is172]) {
    for (final ip in ips) {
      if (match(ip, test)) return ip;
    }
  }
  if (ips.isEmpty) return null;
  return ips.first;
}

bool _is192(String ip) => ip.startsWith('192.168.');

bool _is10(String ip) => ip.startsWith('10.');

bool _is172(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4 || parts[0] != '172') return false;
  final second = int.tryParse(parts[1]);
  return second != null && second >= 16 && second <= 31;
}

String _html({
  required String link,
  required Uri address,
  required String token,
  required List<String> ips,
}) {
  final svg = _qrSvg(link);
  final others = ips
      .map((ip) => 'http://$ip:${address.port}')
      .map((item) => '<li>${_escape(item)}</li>')
      .join();
  return '''
<!DOCTYPE html>
<html lang="ru">
<meta charset="utf-8">
<title>Field BIM Viewer</title>
<body style="font-family: sans-serif; max-width: 40rem; margin: 2rem auto;">
<h1>Тестовое подключение</h1>
<p>Откройте этот файл на компьютере и отсканируйте код в приложении.</p>
$svg
<p>Адрес: ${_escape(address.toString())}</p>
<p>Токен: ${_escape(token)}</p>
<p>Ссылка: ${_escape(link)}</p>
<ul>$others</ul>
</body>
</html>
''';
}

String _escape(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _qrSvg(String data) {
  final code = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(code);
  final count = image.moduleCount;
  const quiet = 4;
  final cells = count + quiet * 2;
  final buffer = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $cells $cells" width="360" height="360">',
    )
    ..writeln('<rect width="$cells" height="$cells" fill="white"/>');
  for (var row = 0; row < count; row++) {
    for (var col = 0; col < count; col++) {
      if (!image.isDark(row, col)) continue;
      final x = col + quiet;
      final y = row + quiet;
      buffer.writeln('<rect x="$x" y="$y" width="1" height="1"/>');
    }
  }
  buffer.writeln('</svg>');
  return buffer.toString();
}
