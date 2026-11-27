import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'strings.dart';
import 'sync.dart';

/// `fbv://connect?url=<http(s) base>&token=<secret>`.
///
/// The same text is the QR code and the Android deep link. The token is
/// optional: a server that was not given one still accepts the pull.
class ServerLink {
  const ServerLink(this.address, this.token);

  final Uri address;
  final String token;

  String encode() {
    return Uri(
      scheme: 'fbv',
      host: 'connect',
      queryParameters: {
        'url': address.toString(),
        if (token.isNotEmpty) 'token': token,
      },
    ).toString();
  }

  static ServerLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'fbv' || uri.host != 'connect') {
      return null;
    }
    final url = uri.queryParameters['url'];
    if (url == null || url.isEmpty) return null;
    final address = Uri.tryParse(url.trim());
    if (address == null || !_httpBase(address)) return null;
    return ServerLink(address, uri.queryParameters['token'] ?? '');
  }
}

bool _httpBase(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}

abstract class TokenStore {
  Future<String> read();
  Future<void> write(String token);
  Future<void> clear();
}

class MemoryTokenStore implements TokenStore {
  String _token = '';

  @override
  Future<String> read() async => _token;

  @override
  Future<void> write(String token) async {
    _token = token;
  }

  @override
  Future<void> clear() async {
    _token = '';
  }
}

/// Android keeps the token in the app Keystore. Other platforms keep it in
/// the user profile, outside the library folder, so a desktop shell can
/// reconnect. Tests pass [MemoryTokenStore] and never touch either store.
class KeystoreTokenStore implements TokenStore {
  static const _channel = MethodChannel('fbv/token');

  @override
  Future<String> read() async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('read') ?? '';
      } catch (_) {
        return '';
      }
    }
    return _desktopRead();
  }

  @override
  Future<void> write(String token) async {
    if (token.isEmpty) {
      await clear();
      return;
    }
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('write', token);
      return;
    }
    _desktopWrite(token);
  }

  @override
  Future<void> clear() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('clear');
      } catch (_) {}
      return;
    }
    final file = _desktopFile();
    if (file.existsSync()) file.deleteSync();
  }

  static File _desktopFile() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    final dir = Directory(p.join(home, '.field-bim-viewer'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'server.token'));
  }

  static String _desktopRead() {
    final file = _desktopFile();
    if (!file.existsSync()) return '';
    try {
      return file.readAsStringSync();
    } catch (_) {
      return '';
    }
  }

  static void _desktopWrite(String token) {
    final file = _desktopFile();
    file.writeAsStringSync(token, flush: true);
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }
}

class ConnectChannel {
  static const _channel = MethodChannel('fbv/connect');

  static Future<String?> take() async {
    if (!Platform.isAndroid) return null;
    try {
      return _channel.invokeMethod<String>('take');
    } catch (_) {
      return null;
    }
  }

  static void bind(void Function(String link) onLink) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final link = call.arguments?.toString() ?? '';
        if (link.isNotEmpty) onLink(link);
      }
    });
  }
}

class QrScanner {
  static const _channel = MethodChannel('fbv/qr');

  static Future<String?> scan({required String title}) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('scan', {'title': title});
  }
}

enum SyncNoticeKind { unavailable, revoked, interrupted }

class SyncNotice {
  const SyncNotice(this.kind, this.message);

  final SyncNoticeKind kind;
  final String message;
}

/// People see [SyncNotice.message]. The socket text stays in the exception.
SyncNotice syncNotice(Object error, S strings) {
  if (error is SyncInterrupted) {
    return SyncNotice(
      SyncNoticeKind.interrupted,
      strings.syncInterrupted(error.path, error.got, error.total),
    );
  }
  if (error is SyncAccessRevoked) {
    return SyncNotice(SyncNoticeKind.revoked, strings.syncRevoked);
  }
  return SyncNotice(SyncNoticeKind.unavailable, strings.syncUnavailable);
}
