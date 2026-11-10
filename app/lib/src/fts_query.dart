/// FTS5 MATCH expression for a user string.
///
/// Each whitespace-separated piece is a quoted prefix. Quoting keeps a hyphen
/// inside a mark such as `НС-12` from being read as a column filter. An empty
/// string means the caller should not apply a search limit.
String? ftsMatchExpression(String query) {
  final parts = <String>[];
  for (final token in query.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    parts.add('"${token.replaceAll('"', '""')}"*');
  }
  if (parts.isEmpty) return null;
  return parts.join(' ');
}
