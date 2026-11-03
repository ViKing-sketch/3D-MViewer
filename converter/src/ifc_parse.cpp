#include "ifc_parse.hpp"

#include <algorithm>
#include <cctype>

namespace fbv {
namespace {

void append_utf8(std::string& out, char32_t cp) {
  if (cp > 0x10FFFF) return;
  if (cp < 0x80) {
    out.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

int hex_value(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

void append_utf16_hex(std::string& out, std::string_view hex) {
  std::vector<std::uint16_t> units;
  std::size_t i = 0;
  while (i + 4 <= hex.size()) {
    int value = 0;
    bool ok = true;
    for (int k = 0; k < 4; ++k) {
      const int nibble = hex_value(hex[i + static_cast<std::size_t>(k)]);
      if (nibble < 0) {
        ok = false;
        break;
      }
      value = (value << 4) | nibble;
    }
    if (!ok) break;
    units.push_back(static_cast<std::uint16_t>(value));
    i += 4;
  }
  for (std::size_t u = 0; u < units.size(); ++u) {
    char32_t cp = units[u];
    if (cp >= 0xD800 && cp <= 0xDBFF && u + 1 < units.size()) {
      const char32_t low = units[u + 1];
      if (low >= 0xDC00 && low <= 0xDFFF) {
        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
        ++u;
      }
    }
    append_utf8(out, cp);
  }
}

class Parser {
 public:
  explicit Parser(std::string_view text) : text_(text) {}

  IfcFile parse() {
    skip_bom();
    read_schema();
    const auto data = text_.find("DATA;");
    if (data == std::string_view::npos) fail("DATA section is missing");
    i_ = data + 5;
    while (true) {
      skip();
      if (starts_with("ENDSEC") || starts_with("END-ISO-10303-21")) break;
      if (i_ >= text_.size()) break;
      parse_entity();
    }
    return std::move(file_);
  }

 private:
  std::string_view text_;
  std::size_t i_ = 0;
  IfcFile file_;

  [[noreturn]] void fail(const std::string& message) const {
    const std::size_t n = std::min<std::size_t>(24, text_.size() - std::min(i_, text_.size()));
    const std::string snippet(text_.substr(std::min(i_, text_.size()), n));
    throw IfcParseError("IFC parse error at " + std::to_string(i_) + ": " + message + " near '" +
                        snippet + "'");
  }

  void skip_bom() {
    if (text_.size() >= 3 && static_cast<unsigned char>(text_[0]) == 0xEF &&
        static_cast<unsigned char>(text_[1]) == 0xBB &&
        static_cast<unsigned char>(text_[2]) == 0xBF) {
      i_ = 3;
    }
  }

  bool starts_with(std::string_view token) const { return text_.substr(i_, token.size()) == token; }

  void skip() {
    while (i_ < text_.size()) {
      const char c = text_[i_];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        ++i_;
        continue;
      }
      if (c == '/' && i_ + 1 < text_.size() && text_[i_ + 1] == '*') {
        i_ += 2;
        while (i_ + 1 < text_.size() && !(text_[i_] == '*' && text_[i_ + 1] == '/')) ++i_;
        if (i_ + 1 < text_.size()) i_ += 2;
        continue;
      }
      break;
    }
  }

  char peek() const { return i_ < text_.size() ? text_[i_] : '\0'; }

  char get() {
    if (i_ >= text_.size()) fail("unexpected end of file");
    return text_[i_++];
  }

  void read_schema() {
    const auto pos = text_.find("FILE_SCHEMA");
    if (pos == std::string_view::npos) {
      file_.schema = "IFC4";
      return;
    }
    std::size_t cursor = pos;
    while (cursor < text_.size() && text_[cursor] != '\'') ++cursor;
    if (cursor >= text_.size()) return;
    ++cursor;
    std::string schema;
    while (cursor < text_.size() && text_[cursor] != '\'') schema.push_back(text_[cursor++]);
    for (char& c : schema) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    file_.schema = schema;
  }

  void parse_entity() {
    if (get() != '#') fail("expected entity id");
    const std::int64_t id = parse_integer();
    skip();
    if (get() != '=') fail("expected '='");
    skip();
    std::string type;
    while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') type.push_back(get());
    for (char& c : type) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    if (type.empty()) fail("expected entity type");
    skip();
    if (get() != '(') fail("expected '('");
    IfcEntity entity;
    entity.id = id;
    entity.type = type;
    skip();
    if (peek() != ')') {
      while (true) {
        entity.attrs.push_back(parse_value());
        skip();
        const char sep = get();
        if (sep == ')') break;
        if (sep != ',') fail("expected comma between attributes");
        skip();
      }
    } else {
      get();
    }
    skip();
    if (get() != ';') fail("expected ';' after entity");
    file_.by_type[entity.type].push_back(id);
    file_.entities.emplace(id, std::move(entity));
  }

  std::int64_t parse_integer() {
    if (!(peek() >= '0' && peek() <= '9')) fail("expected integer");
    std::int64_t value = 0;
    while (peek() >= '0' && peek() <= '9') {
      value = value * 10 + (get() - '0');
    }
    return value;
  }

  IfcValue parse_value() {
    skip();
    const char c = peek();
    if (c == '$') {
      get();
      return {};
    }
    if (c == '*') {
      get();
      IfcValue value;
      value.kind = IfcValue::Kind::Derived;
      return value;
    }
    if (c == '#') {
      get();
      IfcValue value;
      value.kind = IfcValue::Kind::Ref;
      value.i = parse_integer();
      return value;
    }
    if (c == '\'') {
      IfcValue value;
      value.kind = IfcValue::Kind::String;
      value.text = parse_string();
      return value;
    }
    if (c == '(') {
      get();
      IfcValue value;
      value.kind = IfcValue::Kind::List;
      skip();
      if (peek() != ')') {
        while (true) {
          value.items.push_back(parse_value());
          skip();
          const char sep = get();
          if (sep == ')') break;
          if (sep != ',') fail("expected comma in list");
          skip();
        }
      } else {
        get();
      }
      return value;
    }
    if (c == '.') {
      get();
      IfcValue value;
      value.kind = IfcValue::Kind::Enum;
      while (peek() && peek() != '.') value.text.push_back(get());
      if (get() != '.') fail("unterminated enumeration");
      for (char& ch : value.text)
        ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
      return value;
    }
    if (c == '-' || c == '+' || (c >= '0' && c <= '9')) return parse_number();
    if (std::isalpha(static_cast<unsigned char>(c))) return parse_typed();
    fail("expected value");
  }

  std::string parse_string() {
    if (get() != '\'') fail("expected string");
    std::string raw;
    while (true) {
      const char c = get();
      if (c == '\'') {
        if (peek() == '\'') {
          get();
          raw.push_back('\'');
          continue;
        }
        break;
      }
      raw.push_back(c);
    }
    return decode_ifc_string(raw);
  }

  IfcValue parse_number() {
    const std::size_t start = i_;
    if (peek() == '+' || peek() == '-') get();
    bool any = false;
    while (peek() >= '0' && peek() <= '9') {
      any = true;
      get();
    }
    bool real = false;
    if (peek() == '.') {
      real = true;
      get();
      while (peek() >= '0' && peek() <= '9') {
        any = true;
        get();
      }
    }
    if (peek() == 'E' || peek() == 'e') {
      real = true;
      get();
      if (peek() == '+' || peek() == '-') get();
      if (!(peek() >= '0' && peek() <= '9')) fail("expected exponent");
      while (peek() >= '0' && peek() <= '9') get();
    }
    if (!any) fail("expected number");
    const std::string token(text_.substr(start, i_ - start));
    IfcValue value;
    try {
      if (!real) {
        value.kind = IfcValue::Kind::Integer;
        value.i = std::stoll(token);
        value.real = static_cast<double>(value.i);
      } else {
        value.kind = IfcValue::Kind::Real;
        value.real = std::stod(token);
        value.i = static_cast<std::int64_t>(value.real);
      }
    } catch (const std::exception&) {
      fail("bad number");
    }
    return value;
  }

  IfcValue parse_typed() {
    std::string name;
    while (std::isalnum(static_cast<unsigned char>(peek())) || peek() == '_') name.push_back(get());
    for (char& c : name) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    skip();
    if (get() != '(') fail("expected '(' after type");
    IfcValue value;
    value.kind = IfcValue::Kind::Typed;
    value.text = name;
    value.items.push_back(parse_value());
    skip();
    if (get() != ')') fail("expected ')' after typed value");
    return value;
  }
};

}  // namespace

namespace {

// Windows-1251 for 0x80..0xBF. 0xC0..0xFF is U+0410..U+044F.
const char32_t kCp1251Low[] = {
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409,
    0x2039, 0x040A, 0x040C, 0x040B, 0x040F, 0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022,
    0x2013, 0x2014, 0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, 0x00A0,
    0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB,
    0x00AC, 0x00AD, 0x00AE, 0x0407, 0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6,
    0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457};

void append_cp(std::string& out, char32_t cp) {
  if (cp > 0x10FFFF) return;
  if (cp < 0x80) {
    out.push_back(static_cast<char>(cp));
  } else if (cp < 0x800) {
    out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else if (cp < 0x10000) {
    out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  } else {
    out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
    out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
  }
}

char32_t cp1251_byte(unsigned char c) {
  if (c < 0x80) return c;
  if (c < 0xC0) return kCp1251Low[c - 0x80];
  return 0x0410 + (c - 0xC0);
}

// Keep well-formed UTF-8. A lone continuation or an illegal lead (what Dart
// reports as "Unexpected extension byte") is a code-page byte from an IFC
// \S or \X escape, or from a Windows-1251 file copied through unchanged.
std::string sanitize_stored_text(std::string_view in) {
  std::string out;
  out.reserve(in.size());
  for (std::size_t i = 0; i < in.size();) {
    const auto c = static_cast<unsigned char>(in[i]);
    if (c < 0x80) {
      out.push_back(static_cast<char>(c));
      ++i;
      continue;
    }
    int need = 0;
    if (c >= 0xC2 && c <= 0xDF) need = 2;
    else if ((c & 0xF0) == 0xE0) need = 3;
    else if (c >= 0xF0 && c <= 0xF4) need = 4;
    bool ok = need > 1 && i + static_cast<std::size_t>(need) <= in.size();
    for (int k = 1; ok && k < need; ++k) {
      if ((static_cast<unsigned char>(in[i + static_cast<std::size_t>(k)]) & 0xC0) != 0x80) ok = false;
    }
    if (ok) {
      out.append(in.substr(i, static_cast<std::size_t>(need)));
      i += static_cast<std::size_t>(need);
      continue;
    }
    append_cp(out, cp1251_byte(c));
    ++i;
  }
  return out;
}

}  // namespace

std::string decode_ifc_string(std::string_view raw) {
  std::string out;
  for (std::size_t i = 0; i < raw.size(); ++i) {
    if (raw[i] != '\\') {
      out.push_back(raw[i]);
      continue;
    }
    if (i + 1 < raw.size() && raw[i + 1] == '\\') {
      out.push_back('\\');
      ++i;
      continue;
    }
    if (i + 3 < raw.size() && raw[i + 1] == 'X' && raw[i + 2] == '2' && raw[i + 3] == '\\') {
      i += 4;
      const std::size_t start = i;
      while (i + 3 < raw.size() &&
             !(raw[i] == '\\' && raw[i + 1] == 'X' && raw[i + 2] == '0' && raw[i + 3] == '\\')) {
        ++i;
      }
      append_utf16_hex(out, raw.substr(start, i - start));
      if (i + 3 < raw.size()) i += 3;
      continue;
    }
    if (i + 3 < raw.size() && raw[i + 1] == 'X' && raw[i + 2] == '4' && raw[i + 3] == '\\') {
      i += 4;
      const std::size_t start = i;
      while (i + 3 < raw.size() &&
             !(raw[i] == '\\' && raw[i + 1] == 'X' && raw[i + 2] == '0' && raw[i + 3] == '\\')) {
        ++i;
      }
      const auto hex = raw.substr(start, i - start);
      for (std::size_t h = 0; h + 8 <= hex.size(); h += 8) {
        char32_t cp = 0;
        bool ok = true;
        for (int k = 0; k < 8; ++k) {
          const int nibble = hex_value(hex[h + static_cast<std::size_t>(k)]);
          if (nibble < 0) {
            ok = false;
            break;
          }
          cp = (cp << 4) | static_cast<char32_t>(nibble);
        }
        if (ok) append_utf8(out, cp);
      }
      if (i + 3 < raw.size()) i += 3;
      continue;
    }
    if (i + 3 < raw.size() && raw[i + 1] == 'X' && raw[i + 2] == '\\') {
      const int hi = hex_value(i + 3 < raw.size() ? raw[i + 3] : '\0');
      const int lo = i + 4 < raw.size() ? hex_value(raw[i + 4]) : -1;
      if (hi >= 0 && lo >= 0) {
        // ISO 10303-21 \X\hh is one byte in the current code page. The default
        // page is ISO-8859-1, so the byte is a Unicode code point, not a UTF-8 unit.
        append_cp(out, static_cast<char32_t>((hi << 4) | lo));
        i += 4;
        continue;
      }
    }
    if (i + 2 < raw.size() && raw[i + 1] == 'S' && raw[i + 2] == '\\' && i + 3 < raw.size()) {
      append_cp(out, static_cast<char32_t>(static_cast<unsigned char>(raw[i + 3]) + 128));
      i += 3;
      continue;
    }
    if (i + 3 < raw.size() && raw[i + 1] == 'P' &&
        std::isalpha(static_cast<unsigned char>(raw[i + 2])) && raw[i + 3] == '\\') {
      i += 3;
      continue;
    }
    out.push_back('\\');
  }
  return sanitize_stored_text(out);
}

const IfcEntity* IfcFile::find(std::int64_t id) const {
  const auto it = entities.find(id);
  return it == entities.end() ? nullptr : &it->second;
}

std::vector<const IfcEntity*> IfcFile::typed(const std::string& type) const {
  std::vector<const IfcEntity*> out;
  const auto it = by_type.find(type);
  if (it == by_type.end()) return out;
  out.reserve(it->second.size());
  for (std::int64_t id : it->second) {
    if (const IfcEntity* entity = find(id)) out.push_back(entity);
  }
  return out;
}

IfcFile parse_ifc(std::string_view text) {
  Parser parser(text);
  return parser.parse();
}

}  // namespace fbv
