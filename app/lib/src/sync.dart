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
///
/// An optional `Authorization: Bearer` token is checked only when the server
/// was started with one. The token is not written into `.fbv-sync.json`.
const syncProtocol = 'fbv-sync-1';

class SyncSettings {
  const SyncSettings({
    this.serverUrl = '',
    this.setup = '',
    this.serverPackages = const [],
  });

  final String serverUrl;

  /// `local`, `server`, or empty when the first-run choice is still open.
  ///
  /// A file written before this field existed, with only `server_url`, loads
  /// as `server`.
  final String setup;

  /// Library-relative package names last seen on the server.
  final List<String> serverPackages;

  static File fileIn(String libraryRoot) =>
      File(p.join(libraryRoot, '.fbv-sync.json'));

  static SyncSettings load(String libraryRoot) {
    final file = fileIn(libraryRoot);
    if (!file.existsSync()) return const SyncSettings();
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const SyncSettings();
      final url = decoded['server_url'];
      final serverUrl = url is String ? url : '';
      final setupRaw = decoded['setup'];
      var setup = setupRaw is String ? setupRaw : '';
      if (setup != 'local' && setup != 'server') setup = '';
      if (setup.isEmpty && serverUrl.isNotEmpty) setup = 'server';
      final listed = decoded['server_packages'];
      final packages = <String>[];
      if (listed is List) {
        for (final item in listed) {
          if (item is String && syncPathAllowed(item) && !item.contains('/')) {
            packages.add(item);
          }
        }
      }
      return SyncSettings(
        serverUrl: serverUrl,
        setup: setup,
        serverPackages: packages,
      );
    } catch (_) {
      return const SyncSettings();
    }
  }

  void save(String libraryRoot) {
    final file = fileIn(libraryRoot);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'server_url': serverUrl,
        'setup': setup,
        'server_packages': serverPackages,
      }),
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
  const SyncPull({
    required this.copied,
    required this.kept,
    this.packages = const [],
  });

  final int copied;
  final int kept;

  /// Package file or directory names listed by the manifest.
  final List<String> packages;
}

/// The server expected a bearer token and this request did not match.
class SyncAccessRevoked implements Exception {
  const SyncAccessRevoked();

  @override
  String toString() => 'sync access revoked';
}

/// Top-level package names in a manifest. Sidecars are not names.
List<String> syncPackageNames(SyncManifest manifest) {
  final names = <String>{};
  for (final file in manifest.files) {
    final slash = file.path.indexOf('/');
    if (slash > 0) {
      names.add(file.path.substring(0, slash));
    } else if (file.path.toLowerCase().endsWith('.fbvpkg')) {
      names.add(file.path);
    }
  }
  final listed = names.toList()..sort();
  return listed;
}

/// The transfer stopped before the manifest length was on disk.
///
/// The previous file in the library is left as it was. Bytes already
/// received stay in `.fbv-sync-parts` and the next pull continues with
/// `Range`.
class SyncInterrupted implements Exception {
  const SyncInterrupted(this.path, this.got, this.total);

  final String path;
  final int got;
  final int total;

  @override
  String toString() => 'sync interrupted $path $got/$total';
}

class SyncServer {
  SyncServer._(this.server, this.rootPath);

  final HttpServer server;
  final String rootPath;

  /// Stops each file body after this many bytes. Null sends the whole body.
  ///
  /// A listener on a real peer leaves this null. Tests set it to drop a
  /// transfer in the middle of one file.
  int? responseByteLimit;

  /// Range headers seen by file requests, including null when the header is
  /// absent. Tests read this. A listener does not.
  final List<String?> requestRanges = [];

  /// When set, every request must send `Authorization: Bearer` with this
  /// exact value. The in-app listener leaves it null.
  String? expectedToken;

  Uri get base => Uri.parse('http://${server.address.host}:${server.port}');

  static Future<SyncServer> start(
    String rootPath, {
    InternetAddress? address,
    int port = 0,
    String? expectedToken,
  }) async {
    final root = Directory(rootPath);
    if (!root.existsSync()) root.createSync(recursive: true);
    final bound = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    final endpoint = SyncServer._(bound, root.absolute.path);
    endpoint.expectedToken = expectedToken;
    bound.listen(endpoint._handle);
    return endpoint;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    try {
      final expected = expectedToken;
      if (expected != null && expected.isNotEmpty) {
        final header = request.headers.value(HttpHeaders.authorizationHeader);
        if (header != 'Bearer $expected') {
          request.response.statusCode = HttpStatus.unauthorized;
          return;
        }
      }
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
    final length = file.lengthSync();
    requestRanges.add(request.headers.value(HttpHeaders.rangeHeader));
    final ({int start, int end})? range;
    try {
      range = _byteRange(
        request.headers.value(HttpHeaders.rangeHeader),
        length,
      );
    } on FormatException {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$length',
      );
      return;
    }
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentType = ContentType.binary;
    if (range != null) {
      final last = range.end == 0 ? 0 : range.end - 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-$last/$length',
      );
    }
    if (length == 0 || (range != null && range.start == range.end)) return;
    final opened = range == null
        ? file.openRead()
        : file.openRead(range.start, range.end);
    var remaining = responseByteLimit;
    await for (final chunk in opened) {
      var slice = chunk;
      if (remaining != null) {
        if (remaining <= 0) break;
        if (slice.length > remaining) slice = slice.sublist(0, remaining);
        remaining -= slice.length;
      }
      request.response.add(slice);
      if (remaining != null && remaining <= 0) break;
    }
  }
}

/// `bytes=START-` or `bytes=START-END`, END inclusive. Null means the whole file.
({int start, int end})? _byteRange(String? header, int length) {
  if (header == null || header.isEmpty) return null;
  final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header.trim());
  if (match == null) throw const FormatException('range');
  final start = int.parse(match.group(1)!);
  if (start < 0 || start >= length) throw const FormatException('range');
  final endText = match.group(2)!;
  final last = endText.isEmpty ? length - 1 : int.parse(endText);
  if (last < start || last >= length) throw const FormatException('range');
  return (start: start, end: last + 1);
}

Future<SyncPull> pullLibrary(
  String rootPath,
  Uri base, {
  String token = '',
}) async {
  final root = Directory(rootPath);
  root.createSync(recursive: true);
  final manifestUri = base.replace(path: '/fbv-sync/manifest', query: '');
  final client = HttpClient();
  try {
    final manifest = SyncManifest.fromJson(
      jsonDecode(await _getText(client, manifestUri, token)),
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
      await _resumeFile(client, root.path, base, remote, token);
      copied += 1;
    }
    return SyncPull(
      copied: copied,
      kept: kept,
      packages: syncPackageNames(manifest),
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _resumeFile(
  HttpClient client,
  String rootPath,
  Uri base,
  SyncFile remote,
  String token,
) async {
  final root = Directory(rootPath);
  final dest = File(p.join(root.path, remote.path));
  if (!p.isWithin(root.absolute.path, dest.absolute.path)) {
    throw const FileSystemException('sync path leaves the library');
  }
  final uri = base.replace(
    path: '/fbv-sync/file',
    queryParameters: {'path': remote.path},
  );
  var got = _usablePart(rootPath, remote);
  var response = await _openFile(client, uri, got, token);
  if (response.statusCode == HttpStatus.unauthorized ||
      response.statusCode == HttpStatus.forbidden) {
    await response.drain<void>();
    throw const SyncAccessRevoked();
  }
  if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
    await response.drain<void>();
    _deletePart(rootPath, remote.path);
    got = 0;
    response = await _openFile(client, uri, 0, token);
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      await response.drain<void>();
      throw const SyncAccessRevoked();
    }
  }
  if (response.statusCode == HttpStatus.ok) {
    if (got != 0) {
      _deletePart(rootPath, remote.path);
      got = 0;
    }
  } else if (response.statusCode == HttpStatus.partialContent) {
    final start = _contentRangeStart(
      response.headers.value(HttpHeaders.contentRangeHeader),
    );
    if (start != got) {
      await response.drain<void>();
      _deletePart(rootPath, remote.path);
      throw SyncInterrupted(remote.path, 0, remote.bytes);
    }
  } else {
    final code = response.statusCode;
    await response.drain<void>();
    throw HttpException('sync $code $uri', uri: uri);
  }
  try {
    got = await _writeBody(response, _partBin(rootPath, remote.path), got);
  } catch (_) {
    final have = _partLength(rootPath, remote.path);
    _storePart(rootPath, remote, have);
    throw SyncInterrupted(remote.path, have, remote.bytes);
  }
  if (got != remote.bytes) {
    _storePart(rootPath, remote, got);
    throw SyncInterrupted(remote.path, got, remote.bytes);
  }
  final part = _partBin(rootPath, remote.path);
  final digest = (await part.openRead().transform(sha256).first).toString();
  if (digest != remote.sha256) {
    _deletePart(rootPath, remote.path);
    throw const FileSystemException('sync hash does not match the manifest');
  }
  dest.parent.createSync(recursive: true);
  part.renameSync(dest.path);
  _deletePart(rootPath, remote.path);
  dest.setLastModifiedSync(remote.mtimeUtc);
}

void _authorize(HttpClientRequest request, String token) {
  if (token.isEmpty) return;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
}

Future<HttpClientResponse> _openFile(
  HttpClient client,
  Uri uri,
  int offset,
  String token,
) async {
  final request = await client.getUrl(uri);
  _authorize(request, token);
  if (offset > 0) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
  }
  return request.close();
}

Future<int> _writeBody(
  HttpClientResponse response,
  File part,
  int start,
) async {
  part.parent.createSync(recursive: true);
  final sink = part.openWrite(
    mode: start == 0 ? FileMode.write : FileMode.append,
  );
  var got = start;
  try {
    await for (final chunk in response) {
      sink.add(chunk);
      got += chunk.length;
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
  return got;
}

int? _contentRangeStart(String? header) {
  if (header == null) return null;
  final match = RegExp(r'^bytes (\d+)-').firstMatch(header.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!);
}

String _partKey(String relative) =>
    sha256.convert(utf8.encode(relative)).toString();

Directory _partDir(String rootPath) =>
    Directory(p.join(rootPath, '.fbv-sync-parts'));

File _partBin(String rootPath, String relative) =>
    File(p.join(_partDir(rootPath).path, '${_partKey(relative)}.bin'));

File _partMeta(String rootPath, String relative) =>
    File(p.join(_partDir(rootPath).path, '${_partKey(relative)}.json'));

int _partLength(String rootPath, String relative) {
  final bin = _partBin(rootPath, relative);
  if (!bin.existsSync()) return 0;
  return bin.lengthSync();
}

int _usablePart(String rootPath, SyncFile remote) {
  final bin = _partBin(rootPath, remote.path);
  final metaFile = _partMeta(rootPath, remote.path);
  if (!bin.existsSync() || !metaFile.existsSync()) return 0;
  try {
    final decoded = jsonDecode(metaFile.readAsStringSync());
    if (decoded is! Map) return 0;
    if (decoded['path'] != remote.path ||
        decoded['sha256'] != remote.sha256 ||
        decoded['bytes'] != remote.bytes) {
      return 0;
    }
    final got = decoded['got'];
    if (got is! int || got <= 0 || got >= remote.bytes) return 0;
    if (bin.lengthSync() != got) return 0;
    return got;
  } catch (_) {
    return 0;
  }
}

void _storePart(String rootPath, SyncFile remote, int got) {
  final bin = _partBin(rootPath, remote.path);
  if (got <= 0 || got >= remote.bytes || !bin.existsSync()) {
    _deletePart(rootPath, remote.path);
    return;
  }
  if (bin.lengthSync() != got) {
    _deletePart(rootPath, remote.path);
    return;
  }
  final meta = _partMeta(rootPath, remote.path);
  meta.parent.createSync(recursive: true);
  meta.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'path': remote.path,
      'sha256': remote.sha256,
      'bytes': remote.bytes,
      'got': got,
    }),
  );
}

void _deletePart(String rootPath, String relative) {
  final bin = _partBin(rootPath, relative);
  final meta = _partMeta(rootPath, relative);
  if (bin.existsSync()) bin.deleteSync();
  if (meta.existsSync()) meta.deleteSync();
}

Future<String> _getText(HttpClient client, Uri uri, String token) async {
  final request = await client.getUrl(uri);
  _authorize(request, token);
  final response = await request.close();
  if (response.statusCode == HttpStatus.unauthorized ||
      response.statusCode == HttpStatus.forbidden) {
    await response.drain<void>();
    throw const SyncAccessRevoked();
  }
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('sync ${response.statusCode} $uri', uri: uri);
  }
  return utf8.decode(
    await response.fold<List<int>>([], (a, b) => a..addAll(b)),
  );
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
