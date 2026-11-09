import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// A remark stored beside a package, not inside it.
///
/// [elementId] is the id in this package. [guid] is the IFC GlobalId, which
/// is what a BCF viewpoint can point at. A photo is a file copied next to the
/// sidecar. Nothing here is written into `.fbvpkg` or `brep.pack`.
class Remark {
  Remark({
    required this.id,
    required this.elementId,
    required this.guid,
    required this.text,
    required this.createdUtc,
    this.photoName,
  });

  final String id;
  final int? elementId;
  final String guid;
  final String text;
  final String createdUtc;
  final String? photoName;

  Map<String, Object?> toJson() => {
    'id': id,
    'element_id': elementId,
    'guid': guid,
    'text': text,
    'created_utc': createdUtc,
    'photo': photoName,
  };

  static Remark fromJson(Map<String, Object?> json) {
    return Remark(
      id: json['id'] as String? ?? '',
      elementId: json['element_id'] as int?,
      guid: json['guid'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdUtc: json['created_utc'] as String? ?? '',
      photoName: json['photo'] as String?,
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

  void exportBcf(String zipPath) {
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
          _viewpointXml(viewpointId, remark.guid),
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
  int importBcf(String zipPath, Map<String, int> guidToElement) {
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
      final guid = viewpoint == null
          ? ''
          : (_attr(utf8.decode(viewpoint), 'Component', 'IfcGuid') ?? '');
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

String _viewpointXml(String viewpointId, String guid) {
  final selection = guid.isEmpty
      ? ''
      : '      <Component IfcGuid="${_xml(guid)}"/>\n';
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<VisualizationInfo Guid="${_xml(viewpointId)}">\n'
      '  <Components>\n'
      '    <Selection>\n'
      '$selection'
      '    </Selection>\n'
      '  </Components>\n'
      '</VisualizationInfo>\n';
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
