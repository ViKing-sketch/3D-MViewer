import 'dart:convert';
import 'dart:io';

import 'remarks.dart';

/// A named view of one model, stored beside the package.
///
/// The sidecar is `<package>.views.json`. It is not a remark, not a BCF topic
/// and not a file inside `.fbvpkg`. [viewpoint] is the same camera, filter,
/// hidden, isolated and single section plane a remark can remember. [xray]
/// is extra: a remark does not store it. Opening the view later puts the
/// camera back on orbit. The pose is not a walk that stops at walls.
class NamedView {
  const NamedView({
    required this.id,
    required this.name,
    required this.createdUtc,
    required this.viewpoint,
    required this.xray,
  });

  final String id;
  final String name;
  final String createdUtc;
  final RemarkViewpoint viewpoint;
  final bool xray;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'created_utc': createdUtc,
    'xray': xray,
    'viewpoint': viewpoint.toJson(),
  };

  static NamedView? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty || name.trim().length > 80) {
      return null;
    }
    final viewpoint = RemarkViewpoint.fromJson(json['viewpoint']);
    if (viewpoint == null) return null;
    return NamedView(
      id: id,
      name: name.trim(),
      createdUtc: json['created_utc'] as String? ?? '',
      viewpoint: viewpoint,
      xray: json['xray'] == true,
    );
  }
}

/// Empty or over-long name. The store does not write the sidecar in this case.
class NamedViewNameException implements Exception {
  const NamedViewNameException({required this.empty});

  final bool empty;
}

/// JSON sidecar `<package>.views.json`.
///
/// Nothing here is written into the package directory, `brep.pack` or the
/// remarks sidecar. `fbv-sync-1` does not list this file.
class NamedViewStore {
  NamedViewStore(this.packagePath, {DateTime Function()? now, RemarkIds? ids})
    : _now = now ?? DateTime.now,
      _ids = ids ?? RemarkIds();

  static const kind = 'fbv-views-1';
  static const maxNameLength = 80;

  final String packagePath;
  final DateTime Function() _now;
  final RemarkIds _ids;
  final List<NamedView> views = [];
  String? loadError;

  String get jsonPath => '$packagePath.views.json';

  void load() {
    views.clear();
    loadError = null;
    final file = File(jsonPath);
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        loadError = 'views json is not an object';
        return;
      }
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));
      final storedKind = json['kind'];
      if (storedKind != null && storedKind != kind) {
        loadError = 'views kind $storedKind';
        return;
      }
      final list = json['views'];
      if (list is! List) {
        loadError = 'views list missing';
        return;
      }
      for (final item in list) {
        final view = NamedView.fromJson(item);
        if (view != null) views.add(view);
      }
    } catch (error) {
      views.clear();
      loadError = error.toString();
    }
  }

  void save() {
    final file = File(jsonPath);
    file.parent.createSync(recursive: true);
    final payload = const JsonEncoder.withIndent('  ').convert({
      'kind': kind,
      'views': [for (final view in views) view.toJson()],
    });
    final tmp = File('$jsonPath.fbv-tmp');
    tmp.writeAsStringSync(payload);
    tmp.renameSync(file.path);
  }

  NamedView add({
    required String name,
    required RemarkViewpoint viewpoint,
    required bool xray,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const NamedViewNameException(empty: true);
    }
    if (trimmed.length > maxNameLength) {
      throw const NamedViewNameException(empty: false);
    }
    final view = NamedView(
      id: _ids.next(),
      name: trimmed,
      createdUtc: _now().toUtc().toIso8601String(),
      viewpoint: viewpoint,
      xray: xray,
    );
    views.add(view);
    save();
    return view;
  }

  void remove(String id) {
    final before = views.length;
    views.removeWhere((view) => view.id == id);
    if (views.length != before) save();
  }
}
