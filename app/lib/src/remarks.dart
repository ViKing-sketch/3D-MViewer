import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'filament_channel.dart';
import 'walk_pose.dart';

/// A remark stored beside a package, not inside it.
///
/// [elementId] is the id in this package. [guid] is the IFC GlobalId, which
/// is what a BCF viewpoint can point at. A photo is a file copied next to the
/// sidecar. Nothing here is written into `.fbvpkg` or `brep.pack`.
/// Camera and the filters that were active when the remark was written.
///
/// [eyeX], [eyeY], [eyeZ] and the direction are package metres, Z-up, with
/// `local_origin` already subtracted. That is the same space as the mesh
/// after the converter shift. A BCF viewpoint adds the origin back so another
/// viewer opens the IFC place, not the shifted package place.
class RemarkViewpoint {
  const RemarkViewpoint({
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.dirX,
    required this.dirY,
    required this.dirZ,
    this.upX = 0,
    this.upY = 0,
    this.upZ = 1,
    this.storeyId,
    this.ifcClass,
    this.material,
    this.systemId,
    this.section = const SectionView(),
    this.hidden = const [],
    this.isolated = const [],
  });

  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double dirX;
  final double dirY;
  final double dirZ;
  final double upX;
  final double upY;
  final double upZ;
  final int? storeyId;
  final String? ifcClass;

  /// Null means the material filter is off. An empty string is a real filter.
  final String? material;
  final int? systemId;
  final SectionView section;
  final List<int> hidden;
  final List<int> isolated;

  /// Filament is Y-up: package (x, y, z) becomes (x, z, -y).
  ({List<double> eye, List<double> target}) get filament {
    final eye = _filamentFromPackage(eyeX, eyeY, eyeZ);
    final dir = _filamentFromPackage(dirX, dirY, dirZ);
    return (
      eye: [eye.$1, eye.$2, eye.$3],
      target: [eye.$1 + dir.$1, eye.$2 + dir.$2, eye.$3 + dir.$3],
    );
  }

  Map<String, Object?> toJson() => {
    'eye': [eyeX, eyeY, eyeZ],
    'direction': [dirX, dirY, dirZ],
    'up': [upX, upY, upZ],
    'storey_id': storeyId,
    'ifc_class': ifcClass,
    'material': material,
    'system_id': systemId,
    'section': section.toJson(),
    'hidden': hidden,
    'isolated': isolated,
  };

  static RemarkViewpoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final eye = _triple(json['eye']);
    final dir = _triple(json['direction']);
    if (eye == null || dir == null) return null;
    final up = _triple(json['up']) ?? const [0, 0, 1];
    final sectionRaw = json['section'];
    return RemarkViewpoint(
      eyeX: eye[0],
      eyeY: eye[1],
      eyeZ: eye[2],
      dirX: dir[0],
      dirY: dir[1],
      dirZ: dir[2],
      upX: up[0],
      upY: up[1],
      upZ: up[2],
      storeyId: json['storey_id'] as int?,
      ifcClass: json['ifc_class'] as String?,
      material: json['material'] as String?,
      systemId: json['system_id'] as int?,
      section: _section(sectionRaw),
      hidden: _ints(json['hidden']),
      isolated: _ints(json['isolated']),
    );
  }
}

class Remark {
  Remark({
    required this.id,
    required this.elementId,
    required this.guid,
    required this.text,
    required this.createdUtc,
    this.photoName,
    this.viewpoint,
  });

  final String id;
  final int? elementId;
  final String guid;
  final String text;
  final String createdUtc;
  final String? photoName;
  final RemarkViewpoint? viewpoint;

  Map<String, Object?> toJson() => {
    'id': id,
    'element_id': elementId,
    'guid': guid,
    'text': text,
    'created_utc': createdUtc,
    'photo': photoName,
    'viewpoint': viewpoint?.toJson(),
  };

  static Remark fromJson(Map<String, Object?> json) {
    return Remark(
      id: json['id'] as String? ?? '',
      elementId: json['element_id'] as int?,
      guid: json['guid'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdUtc: json['created_utc'] as String? ?? '',
      photoName: json['photo'] as String?,
      viewpoint: RemarkViewpoint.fromJson(json['viewpoint']),
    );
  }
}

class RemarkIds {
  int _n = 0;

  String next() {
    _n += 1;
    final tail = _n.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$tail';
  }
}

/// JSON sidecar `<package>.remarks.json` and photos in `<package>.remarks/`.
class RemarkStore {
  RemarkStore(this.packagePath, {DateTime Function()? now, RemarkIds? ids})
    : _now = now ?? DateTime.now,
      _ids = ids ?? RemarkIds();

  final String packagePath;
  final DateTime Function() _now;
  final RemarkIds _ids;
  final List<Remark> remarks = [];
  String? loadError;

  /// Topics whose GlobalId is not an element of the package they were
  /// imported into. They stay in the sidecar so the text is not dropped.
  int unmatched = 0;

  String get jsonPath => '$packagePath.remarks.json';
  String get folderPath => '$packagePath.remarks';

  void load() {
    remarks.clear();
    loadError = null;
    final file = File(jsonPath);
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final list =
          (decoded as Map<String, Object?>)['remarks'] as List<Object?>;
      for (final item in list) {
        remarks.add(Remark.fromJson(item as Map<String, Object?>));
      }
    } catch (error) {
      loadError = error.toString();
    }
  }

  void save() {
    final file = File(jsonPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'remarks': [for (final remark in remarks) remark.toJson()],
      }),
    );
  }

  List<Remark> forElement(int elementId, String guid) {
    return [
      for (final remark in remarks)
        if (remark.elementId == elementId ||
            (guid.isNotEmpty && remark.guid == guid))
          remark,
    ];
  }

  /// Copies [photoSource] when it is non-empty. The package directory is not
  /// modified.
  Remark add({
    required int elementId,
    required String guid,
    required String text,
    String? photoSource,
    RemarkViewpoint? viewpoint,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('empty remark');
    }
    String? photoName;
    if (photoSource != null && photoSource.trim().isNotEmpty) {
      final source = File(photoSource.trim());
      if (!source.existsSync()) {
        throw FileSystemException('photo not found', photoSource);
      }
      final id = _ids.next();
      final ext = p.extension(source.path);
      photoName = '$id$ext';
      final destDir = Directory(folderPath)..createSync(recursive: true);
      source.copySync(p.join(destDir.path, photoName));
      final remark = Remark(
        id: id,
        elementId: elementId,
        guid: guid,
        text: trimmed,
        createdUtc: _now().toUtc().toIso8601String(),
        photoName: photoName,
        viewpoint: viewpoint,
      );
      remarks.add(remark);
      save();
      return remark;
    }
    final remark = Remark(
      id: _ids.next(),
      elementId: elementId,
      guid: guid,
      text: trimmed,
      createdUtc: _now().toUtc().toIso8601String(),
      viewpoint: viewpoint,
    );
    remarks.add(remark);
    save();
    return remark;
  }

  File? photoFile(Remark remark) {
    final name = remark.photoName;
    if (name == null || name.isEmpty) return null;
    final file = File(p.join(folderPath, name));
    if (!file.existsSync()) return null;
    return file;
  }

  void exportBcf(String zipPath, {List<double> origin = const [0, 0, 0]}) {
    final archive = Archive();
    archive.addFile(ArchiveFile.string('bcf.version', _bcfVersionXml()));
    for (final remark in remarks) {
      final viewpointId = _ids.next();
      final folder = remark.id;
      final photo = photoFile(remark);
      final snapshotName = photo == null ? null : p.basename(photo.path);
      archive.addFile(
        ArchiveFile.string(
          '$folder/markup.bcf',
          _markupXml(remark, viewpointId, snapshotName),
        ),
      );
      archive.addFile(
        ArchiveFile.string(
          '$folder/viewpoint.bcfv',
          _viewpointXml(viewpointId, remark, origin),
        ),
      );
      if (photo != null && snapshotName != null) {
        final bytes = photo.readAsBytesSync();
        archive.addFile(ArchiveFile.bytes('$folder/$snapshotName', bytes));
      }
    }
    final encoded = ZipEncoder().encode(archive);
    final out = File(zipPath);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(encoded);
  }

  /// Reads a BCF 2.1 zip this store wrote, or the same subset from another
  /// tool: one comment and an `IfcGuid` on the viewpoint. [guidToElement]
  /// maps a GlobalId to the element id in the open package. Topics with no
  /// match are kept and counted in [unmatched].
  int importBcf(
    String zipPath,
    Map<String, int> guidToElement, {
    List<double> origin = const [0, 0, 0],
  }) {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, List<int>>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains('..')) {
        throw FormatException('BCF entry escapes the zip: $name');
      }
      files[name] = entry.content;
    }
    final known = {for (final remark in remarks) remark.id};
    var freshUnmatched = 0;
    for (final name in files.keys) {
      if (!name.endsWith('/markup.bcf')) continue;
      final folder = name.substring(0, name.length - '/markup.bcf'.length);
      final markup = utf8.decode(files[name]!);
      final text = _commentText(markup);
      if (text.isEmpty) continue;
      final topicId = _attr(markup, 'Topic', 'Guid') ?? folder;
      if (known.contains(topicId)) continue;
      final viewpointName = _tagText(markup, 'Viewpoint') ?? 'viewpoint.bcfv';
      final viewpointPath = '$folder/$viewpointName';
      final viewpoint = files[viewpointPath];
      final viewpointXml = viewpoint == null ? '' : utf8.decode(viewpoint);
      final guid = viewpointXml.isEmpty
          ? ''
          : (_attr(viewpointXml, 'Component', 'IfcGuid') ?? '');
      final camera = viewpointXml.isEmpty
          ? null
          : _cameraFromBcf(viewpointXml, origin);
      final elementId = guid.isEmpty ? null : guidToElement[guid];
      if (elementId == null) freshUnmatched += 1;
      String? photoName;
      final snapshot = _tagText(markup, 'Snapshot');
      if (snapshot != null && snapshot.isNotEmpty) {
        final snapBytes = files['$folder/$snapshot'];
        if (snapBytes != null) {
          photoName = '$topicId${p.extension(snapshot)}';
          final destDir = Directory(folderPath)..createSync(recursive: true);
          File(p.join(destDir.path, photoName)).writeAsBytesSync(snapBytes);
        }
      }
      remarks.add(
        Remark(
          id: topicId,
          elementId: elementId,
          guid: guid,
          text: text,
          createdUtc:
              _tagText(markup, 'Date') ?? _now().toUtc().toIso8601String(),
          photoName: photoName,
          viewpoint: camera,
        ),
      );
      known.add(topicId);
    }
    unmatched = freshUnmatched;
    save();
    return freshUnmatched;
  }
}

String _bcfVersionXml() =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Version VersionId="2.1">\n'
    '  <DetailedVersion>2.1</DetailedVersion>\n'
    '</Version>\n';

String _markupXml(Remark remark, String viewpointId, String? snapshotName) {
  final snapshot = snapshotName == null
      ? ''
      : '    <Snapshot>${_xml(snapshotName)}</Snapshot>\n';
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<Markup>\n'
      '  <Topic Guid="${_xml(remark.id)}" TopicType="Remark" TopicStatus="Open">\n'
      '    <Title>${_xml(_title(remark.text))}</Title>\n'
      '    <CreationDate>${_xml(remark.createdUtc)}</CreationDate>\n'
      '    <CreationAuthor>field-bim-viewer</CreationAuthor>\n'
      '  </Topic>\n'
      '  <Comment Guid="$viewpointId">\n'
      '    <Date>${_xml(remark.createdUtc)}</Date>\n'
      '    <Author>field-bim-viewer</Author>\n'
      '    <Comment>${_xml(remark.text)}</Comment>\n'
      '  </Comment>\n'
      '  <Viewpoints Guid="$viewpointId">\n'
      '    <Viewpoint>viewpoint.bcfv</Viewpoint>\n'
      '$snapshot'
      '  </Viewpoints>\n'
      '</Markup>\n';
}

String _viewpointXml(String viewpointId, Remark remark, List<double> origin) {
  final guid = remark.guid;
  final selection = guid.isEmpty
      ? ''
      : '      <Component IfcGuid="${_xml(guid)}"/>\n';
  final camera = remark.viewpoint == null
      ? ''
      : _perspectiveXml(remark.viewpoint!, origin);
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<VisualizationInfo Guid="${_xml(viewpointId)}">\n'
      '  <Components>\n'
      '    <Selection>\n'
      '$selection'
      '    </Selection>\n'
      '  </Components>\n'
      '$camera'
      '</VisualizationInfo>\n';
}

String _perspectiveXml(RemarkViewpoint view, List<double> origin) {
  final ox = origin.isNotEmpty ? origin[0] : 0.0;
  final oy = origin.length > 1 ? origin[1] : 0.0;
  final oz = origin.length > 2 ? origin[2] : 0.0;
  return '  <PerspectiveCamera>\n'
      '${_xyz('CameraViewPoint', view.eyeX + ox, view.eyeY + oy, view.eyeZ + oz)}'
      '${_xyz('CameraDirection', view.dirX, view.dirY, view.dirZ)}'
      '${_xyz('CameraUpVector', view.upX, view.upY, view.upZ)}'
      '    <FieldOfView>45</FieldOfView>\n'
      '  </PerspectiveCamera>\n';
}

String _xyz(String tag, double x, double y, double z) {
  return '    <$tag>\n'
      '      <X>${_num(x)}</X>\n'
      '      <Y>${_num(y)}</Y>\n'
      '      <Z>${_num(z)}</Z>\n'
      '    </$tag>\n';
}

String _num(double value) => value.toStringAsFixed(6);

RemarkViewpoint? _cameraFromBcf(String xml, List<double> origin) {
  final eye = _xyzOf(xml, 'CameraViewPoint');
  final dir = _xyzOf(xml, 'CameraDirection');
  if (eye == null || dir == null) return null;
  final up = _xyzOf(xml, 'CameraUpVector') ?? const [0, 0, 1];
  final ox = origin.isNotEmpty ? origin[0] : 0.0;
  final oy = origin.length > 1 ? origin[1] : 0.0;
  final oz = origin.length > 2 ? origin[2] : 0.0;
  final normal = _unit(dir[0], dir[1], dir[2]);
  return RemarkViewpoint(
    eyeX: eye[0] - ox,
    eyeY: eye[1] - oy,
    eyeZ: eye[2] - oz,
    dirX: normal.$1,
    dirY: normal.$2,
    dirZ: normal.$3,
    upX: up[0],
    upY: up[1],
    upZ: up[2],
  );
}

List<double>? _xyzOf(String xml, String tag) {
  final block = _tagText(xml, tag);
  if (block == null) return null;
  final x = double.tryParse(_tagText(block, 'X') ?? '');
  final y = double.tryParse(_tagText(block, 'Y') ?? '');
  final z = double.tryParse(_tagText(block, 'Z') ?? '');
  if (x == null || y == null || z == null) return null;
  return [x, y, z];
}

/// Pose used when the platform view cannot report the live camera.
///
/// A walk pose is stored as it stands, in package metres. Otherwise the eye
/// sits off the element box, looking at its centre. This is not the orbit
/// gesture: that gesture is only available from [viewpointFromFilament].
RemarkViewpoint fallbackViewpoint({
  WalkPose? walk,
  ElementBox? box,
  List<double> origin = const [0, 0, 0],
  int? storeyId,
  String? ifcClass,
  String? material,
  int? systemId,
  SectionView section = const SectionView(),
  List<int> hidden = const [],
  List<int> isolated = const [],
}) {
  final ox = origin.isNotEmpty ? origin[0] : 0.0;
  final oy = origin.length > 1 ? origin[1] : 0.0;
  final oz = origin.length > 2 ? origin[2] : 0.0;
  if (walk != null) {
    final dir = _unit(walk.lookX, walk.lookY, 0);
    return RemarkViewpoint(
      eyeX: walk.eyeX - ox,
      eyeY: walk.eyeY - oy,
      eyeZ: walk.eyeZ - oz,
      dirX: dir.$1,
      dirY: dir.$2,
      dirZ: dir.$3,
      storeyId: storeyId,
      ifcClass: ifcClass,
      material: material,
      systemId: systemId,
      section: section,
      hidden: hidden,
      isolated: isolated,
    );
  }
  final cx = box == null ? 0.0 : (box.minX + box.maxX) / 2 - ox;
  final cy = box == null ? 0.0 : (box.minY + box.maxY) / 2 - oy;
  final cz = box == null ? 0.0 : (box.minZ + box.maxZ) / 2 - oz;
  const span = 6.0;
  final dir = _unit(-span, span, -4);
  return RemarkViewpoint(
    eyeX: cx + span,
    eyeY: cy - span,
    eyeZ: cz + 4,
    dirX: dir.$1,
    dirY: dir.$2,
    dirZ: dir.$3,
    storeyId: storeyId,
    ifcClass: ifcClass,
    material: material,
    systemId: systemId,
    section: section,
    hidden: hidden,
    isolated: isolated,
  );
}

/// Live Filament eye and target, Y-up, into a package viewpoint, Z-up.
RemarkViewpoint viewpointFromFilament({
  required List<double> eye,
  required List<double> target,
  List<double> up = const [0, 1, 0],
  int? storeyId,
  String? ifcClass,
  String? material,
  int? systemId,
  SectionView section = const SectionView(),
  List<int> hidden = const [],
  List<int> isolated = const [],
}) {
  final packageEye = _packageFromFilament(eye[0], eye[1], eye[2]);
  final packageTarget = _packageFromFilament(target[0], target[1], target[2]);
  final packageUp = _packageFromFilament(up[0], up[1], up[2]);
  final dir = _unit(
    packageTarget.$1 - packageEye.$1,
    packageTarget.$2 - packageEye.$2,
    packageTarget.$3 - packageEye.$3,
  );
  return RemarkViewpoint(
    eyeX: packageEye.$1,
    eyeY: packageEye.$2,
    eyeZ: packageEye.$3,
    dirX: dir.$1,
    dirY: dir.$2,
    dirZ: dir.$3,
    upX: packageUp.$1,
    upY: packageUp.$2,
    upZ: packageUp.$3,
    storeyId: storeyId,
    ifcClass: ifcClass,
    material: material,
    systemId: systemId,
    section: section,
    hidden: hidden,
    isolated: isolated,
  );
}

(double, double, double) _packageFromFilament(double x, double y, double z) {
  return (x, -z, y);
}

(double, double, double) _filamentFromPackage(double x, double y, double z) {
  return (x, z, -y);
}

(double, double, double) _unit(double x, double y, double z) {
  final length = (x * x + y * y + z * z);
  if (length < 1e-12) return (0, 1, 0);
  final scale = 1 / math.sqrt(length);
  return (x * scale, y * scale, z * scale);
}

List<double>? _triple(Object? raw) {
  if (raw is! List || raw.length < 3) return null;
  final x = (raw[0] as num?)?.toDouble();
  final y = (raw[1] as num?)?.toDouble();
  final z = (raw[2] as num?)?.toDouble();
  if (x == null || y == null || z == null) return null;
  return [x, y, z];
}

List<int> _ints(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is int) item,
  ];
}

SectionView _section(Object? raw) {
  if (raw is! Map) return const SectionView();
  final json = raw.map((key, value) => MapEntry(key.toString(), value));
  return SectionView(
    enabled: json['enabled'] == true,
    near: (json['near'] as num?)?.toDouble() ?? 0,
    axis: json['axis'] as String? ?? 'x',
    flip: json['flip'] == true,
    offset: (json['offset'] as num?)?.toDouble() ?? 0,
    box: json['box'] == true,
    inset: (json['inset'] as num?)?.toDouble() ?? 0,
  );
}

String _title(String text) {
  final line = text.replaceAll('\n', ' ').trim();
  if (line.length <= 80) return line;
  return line.substring(0, 80);
}

String _xml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _commentText(String markup) {
  final inner = RegExp(r'<Comment>([\s\S]*?)</Comment>').firstMatch(markup);
  if (inner == null) return '';
  return _xmlDecode(inner.group(1) ?? '').trim();
}

String? _tagText(String xml, String tag) {
  final match = RegExp('<$tag>([\\s\\S]*?)</$tag>').firstMatch(xml);
  if (match == null) return null;
  return _xmlDecode(match.group(1) ?? '').trim();
}

String? _attr(String xml, String tag, String name) {
  final match = RegExp('<$tag\\b[^>]*\\b$name="([^"]*)"').firstMatch(xml);
  if (match == null) return null;
  return _xmlDecode(match.group(1) ?? '');
}

String _xmlDecode(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');
