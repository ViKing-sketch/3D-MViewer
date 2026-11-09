import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// One file the library is willing to exchange.
///
/// [path] is relative to the chosen library folder, with `/` separators.
/// Nothing outside that folder is listed. A model that is not already a
/// package, a remarks sidecar, a remarks photo or a BCF next to a package
/// is not part of the exchange.
class SyncFile {
  const SyncFile({
    required this.path,
    required this.bytes,
    required this.sha256,
    required this.mtimeUtc,
  });

  final String path;
  final int bytes;
  final String sha256;
  final DateTime mtimeUtc;

  Map<String, Object> toJson() => {
    'path': path,
    'bytes': bytes,
    'sha256': sha256,
    'mtime_utc': mtimeUtc.toUtc().toIso8601String(),
  };

  static SyncFile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final path = json['path'];
    final digest = json['sha256'];
    final stamp = json['mtime_utc'];
    final bytes = json['bytes'];
    if (path is! String || digest is! String || stamp is! String) return null;
    if (bytes is! int || !syncPathAllowed(path)) return null;
    final mtime = DateTime.tryParse(stamp);
    if (mtime == null) return null;
    return SyncFile(
      path: path,
      bytes: bytes,
      sha256: digest,
      mtimeUtc: mtime.toUtc(),
    );
  }
}

class SyncManifest {
  const SyncManifest(this.files);

  final List<SyncFile> files;

  Map<String, Object> toJson() => {
    'protocol': syncProtocol,
    'files': [for (final file in files) file.toJson()],
  };

  static SyncManifest fromJson(Object? raw) {
    if (raw is! Map) return const SyncManifest([]);
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final listed = json['files'];
    if (listed is! List) return const SyncManifest([]);
    return SyncManifest([for (final item in listed) ?SyncFile.fromJson(item)]);
  }
}

/// Same payload on a LAN peer and on the organisation's server.
///
/// `GET /fbv-sync/manifest` returns [SyncManifest].
/// `GET /fbv-sync/file?path=` returns the bytes of one listed file.
/// A path with `..`, a leading slash, a backslash or an empty segment is
/// rejected. The address is a setting: loopback for a peer on this machine,
/// or the corporate base URL. There is no account and no third-party host.
const syncProtocol = 'fbv-sync-1';

class SyncSettings {
  const SyncSettings({this.serverUrl = ''});

  final String serverUrl;

  static File fileIn(String libraryRoot) =>
      File(p.join(libraryRoot, '.fbv-sync.json'));

  static SyncSettings load(String libraryRoot) {
    final file = fileIn(libraryRoot);
    if (!file.existsSync()) return const SyncSettings();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const SyncSettings();
      final url = decoded['server_url'];
      return SyncSettings(serverUrl: url is String ? url : '');
    } catch (_) {
      return const SyncSettings();
    }
  }

  void save(String libraryRoot) {
    final file = fileIn(libraryRoot);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'server_url': serverUrl}),
    );
  }
}

bool syncPathAllowed(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) return false;
  if (path.contains('\x00')) return false;
  final parts = path.split('/');
  for (final part in parts) {
    if (part.isEmpty || part == '.' || part == '..' || part.startsWith('.')) {
      return false;
    }
  }
  return true;
}

SyncManifest syncCatalog(String rootPath) {
  final root = Directory(rootPath);
  if (!root.existsSync()) return const SyncManifest([]);
  final names = <String>[];
  for (final entity in root.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.startsWith('.') || !syncPathAllowed(name)) continue;
    if (entity is File && name.endsWith('.fbvpkg')) {
      names.add(name);
    } else if (entity is Directory &&
        File(p.join(entity.path, 'manifest.json')).existsSync()) {
      names.add(name);
    }
  }
  final files = <SyncFile>[];
  for (final name in names) {
    final full = p.join(root.path, name);
    if (FileSystemEntity.isDirectorySync(full)) {
      _addTree(files, root.path, name);
    } else {
      _addFile(files, root.path, name);
    }
    _addFile(files, root.path, '$name.remarks.json');
    _addTree(files, root.path, '$name.remarks');
    _addFile(files, root.path, '$name.bcf');
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return SyncManifest(files);
}

class SyncPull {
  const SyncPull({required this.copied, required this.kept});

  final int copied;
  final int kept;
}

class SyncServer {
  SyncServer._(this.server, this.rootPath);

  final HttpServer server;
  final String rootPath;

  Uri get base => Uri.parse('http://${server.address.host}:${server.port}');

  static Future<SyncServer> start(
    String rootPath, {
    InternetAddress? address,
  }) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) root.createSync(recursive: true);
    final bound = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      0,
    );
    final endpoint = SyncServer._(bound, root.absolute.path);
    bound.listen(endpoint._handle);
    return endpoint;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else if (path == '/fbv-sync/manifest') {
        final body = jsonEncode(syncCatalog(rootPath).toJson());
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
      } else if (path == '/fbv-sync/file') {
        await _sendFile(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      request.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await request.response.close();
    }
  }

  Future<void> _sendFile(HttpRequest request) async {
    final relative = request.uri.queryParameters['path'] ?? '';
    final listed = {for (final file in syncCatalog(rootPath).files) file.path};
    if (!syncPathAllowed(relative) || !listed.contains(relative)) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final file = File(p.join(rootPath, relative));
    final root = Directory(rootPath).absolute.path;
    if (!p.isWithin(root, file.absolute.path) || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = ContentType.binary;
    await request.response.addStream(file.openRead());
  }
}

Future<SyncPull> pullLibrary(String rootPath, Uri base) async {
  final root = Directory(rootPath);
  root.createSync(recursive: true);
  final manifestUri = base.replace(path: '/fbv-sync/manifest', query: '');
  final client = HttpClient();
  try {
    final manifest = SyncManifest.fromJson(
      jsonDecode(await _getText(client, manifestUri)),
    );
    final local = {
      for (final file in syncCatalog(rootPath).files) file.path: file,
    };
    var copied = 0;
    var kept = 0;
    for (final remote in manifest.files) {
      final have = local[remote.path];
      if (have != null && have.sha256 == remote.sha256) {
        kept += 1;
        continue;
      }
      if (have != null && !remote.mtimeUtc.isAfter(have.mtimeUtc)) {
        kept += 1;
        continue;
      }
      final bytes = await _getBytes(
        client,
        base.replace(
          path: '/fbv-sync/file',
          queryParameters: {'path': remote.path},
        ),
      );
      final digest = sha256.convert(bytes).toString();
      if (digest != remote.sha256 || bytes.length != remote.bytes) {
        throw const FileSystemException(
          'sync hash does not match the manifest',
        );
      }
      final dest = File(p.join(root.path, remote.path));
      if (!p.isWithin(root.absolute.path, dest.absolute.path)) {
        throw const FileSystemException('sync path leaves the library');
      }
      dest.parent.createSync(recursive: true);
      final tmp = File('${dest.path}.fbv-sync-tmp');
      tmp.writeAsBytesSync(bytes);
      tmp.renameSync(dest.path);
      dest.setLastModifiedSync(remote.mtimeUtc);
      copied += 1;
    }
    return SyncPull(copied: copied, kept: kept);
  } finally {
    client.close(force: true);
  }
}

Future<String> _getText(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('sync ${response.statusCode} $uri', uri: uri);
  }
  return utf8.decode(
    await response.fold<List<int>>([], (a, b) => a..addAll(b)),
  );
}

Future<List<int>> _getBytes(HttpClient client, Uri uri) async {
  final response = await (await client.getUrl(uri)).close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('sync ${response.statusCode} $uri', uri: uri);
  }
  return response.fold<List<int>>([], (a, b) => a..addAll(b));
}

void _addTree(List<SyncFile> files, String root, String relative) {
  final dir = Directory(p.join(root, relative));
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
    _addFile(files, root, rel);
  }
}

void _addFile(List<SyncFile> files, String root, String relative) {
  if (!syncPathAllowed(relative)) return;
  final file = File(p.join(root, relative));
  if (!file.existsSync() ||
      !p.isWithin(Directory(root).absolute.path, file.absolute.path)) {
    return;
  }
  final bytes = file.readAsBytesSync();
  files.add(
    SyncFile(
      path: relative,
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mtimeUtc: file.lastModifiedSync().toUtc(),
    ),
  );
}
