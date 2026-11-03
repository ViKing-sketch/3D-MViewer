import 'dart:convert';
import 'dart:typed_data';

/// Element ids stored in glTF node `extras.elementId`.
///
/// Reads only the GLB JSON chunk. The BIN chunk is not copied.
List<int> glbElementIds(Uint8List bytes) {
  if (bytes.length < 20) return const [];
  if (bytes[0] != 0x67 || bytes[1] != 0x6c || bytes[2] != 0x54 || bytes[3] != 0x46) {
    return const [];
  }
  final jsonLength = _u32(bytes, 12);
  final jsonType = _u32(bytes, 16);
  if (jsonType != 0x4E4F534A || 20 + jsonLength > bytes.length) return const [];
  final text = utf8.decode(bytes.sublist(20, 20 + jsonLength)).trim();
  final decoded = jsonDecode(text);
  if (decoded is! Map) return const [];
  final nodes = decoded['nodes'];
  if (nodes is! List) return const [];
  final ids = <int>[];
  for (final node in nodes) {
    if (node is! Map) continue;
    final extras = node['extras'];
    if (extras is! Map) continue;
    final id = extras['elementId'];
    if (id is num) ids.add(id.toInt());
  }
  return ids;
}

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
