import 'dart:convert';
import 'dart:typed_data';

/// Windows-1251 for bytes 0x80..0xBF. 0xC0..0xFF is U+0410..U+044F.
const _cp1251Low = <int>[
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, //
  0x2039, 0x040A, 0x040C, 0x040B, 0x040F, 0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, //
  0x2013, 0x2014, 0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, 0x00A0, //
  0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, //
  0x00AC, 0x00AD, 0x00AE, 0x0407, 0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, //
  0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
];

/// Package strings are supposed to be UTF-8. Older packages stored `\S\` / `\X\`
/// and Windows-1251 IFC bytes unchanged, which makes `utf8.decode` throw
/// `FormatException: Unexpected extension byte`.
String decodePackageBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return sanitizePackageBytes(bytes);
  }
}

String sanitizePackageBytes(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final c = bytes[i] & 0xff;
    if (c < 0x80) {
      out.writeCharCode(c);
      i++;
      continue;
    }
    var need = 0;
    if (c >= 0xC2 && c <= 0xDF) {
      need = 2;
    } else if ((c & 0xF0) == 0xE0) {
      need = 3;
    } else if (c >= 0xF0 && c <= 0xF4) {
      need = 4;
    }
    var ok = need > 1 && i + need <= bytes.length;
    for (var k = 1; ok && k < need; k++) {
      if ((bytes[i + k] & 0xC0) != 0x80) ok = false;
    }
    if (ok) {
      out.write(utf8.decode(bytes.sublist(i, i + need)));
      i += need;
      continue;
    }
    out.writeCharCode(_cp1251(c));
    i++;
  }
  return out.toString();
}

int _cp1251(int c) {
  if (c < 0x80) return c;
  if (c < 0xC0) return _cp1251Low[c - 0x80];
  return 0x0410 + (c - 0xC0);
}

String packageText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is Uint8List) return decodePackageBytes(value);
  if (value is List<int>) return decodePackageBytes(value);
  return value.toString();
}
