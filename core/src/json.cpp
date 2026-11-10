#include "fbv/json.hpp"

#include <cmath>
#include <cstdio>
#include <sstream>

namespace fbv {
namespace {

class Parser {
 public:
  explicit Parser(std::string_view in) : in_(in) {}

  bool parse(Json& out, std::string& error) {
    try {
      skip();
      out = parse_value();
      skip();
      if (i_ != in_.size()) fail("trailing data");
      return true;
    } catch (const std::runtime_error& ex) {
      error = ex.what();
      return false;
    }
  }

 private:
  std::string_view in_;
  std::size_t i_ = 0;

  [[noreturn]] void fail(const std::string& message) const {
    throw std::runtime_error("json at " + std::to_string(i_) + ": " + message);
  }

  void skip() {
    while (i_ < in_.size()) {
      const char c = in_[i_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++i_;
        continue;
      }
      break;
    }
  }

  char peek() const { return i_ < in_.size() ? in_[i_] : '\0'; }

  char get() {
    if (i_ >= in_.size()) fail("unexpected end");
    return in_[i_++];
  }

  Json parse_value() {
    skip();
    const char c = peek();
    if (c == '{') return parse_object();
    if (c == '[') return parse_array();
    if (c == '"') return Json::string(parse_string());
    if (c == 't' || c == 'f') return Json::boolean(parse_bool());
    if (c == 'n') {
      parse_null();
      return Json::nul();
    }
    if (c == '-' || (c >= '0' && c <= '9')) return parse_number();
    fail("expected value");
  }

  Json parse_object() {
    get();
    Json object = Json::object();
    skip();
    if (peek() == '}') {
      get();
      return object;
    }
    while (true) {
      skip();
      if (peek() != '"') fail("expected key");
      const std::string key = parse_string();
      skip();
      if (get() != ':') fail("expected colon");
      object.set(key, parse_value());
      skip();
      const char sep = get();
      if (sep == '}') break;
      if (sep != ',') fail("expected comma");
    }
    return object;
  }

  Json parse_array() {
    get();
    Json array = Json::array();
    skip();
    if (peek() == ']') {
      get();
      return array;
    }
    while (true) {
      array.push(parse_value());
      skip();
      const char sep = get();
      if (sep == ']') break;
      if (sep != ',') fail("expected comma");
    }
    return array;
  }

  std::string parse_string() {
    if (get() != '"') fail("expected string");
    std::string out;
    while (true) {
      if (i_ >= in_.size()) fail("unterminated string");
      const char c = get();
      if (c == '"') break;
      if (c == '\\') {
        const char e = get();
        switch (e) {
          case '"':
          case '\\':
          case '/':
            out.push_back(e);
            break;
          case 'b':
            out.push_back('\b');
            break;
          case 'f':
            out.push_back('\f');
            break;
          case 'n':
            out.push_back('\n');
            break;
          case 'r':
            out.push_back('\r');
            break;
          case 't':
            out.push_back('\t');
            break;
          case 'u': {
            int code = 0;
            for (int k = 0; k < 4; ++k) {
              const char h = get();
              code <<= 4;
              if (h >= '0' && h <= '9')
                code += h - '0';
              else if (h >= 'a' && h <= 'f')
                code += h - 'a' + 10;
              else if (h >= 'A' && h <= 'F')
                code += h - 'A' + 10;
              else
                fail("bad hex escape");
            }
            append_utf8(out, static_cast<char32_t>(code));
            break;
          }
          default:
            fail("bad escape");
        }
      } else {
        out.push_back(c);
      }
    }
    return out;
  }

  bool parse_bool() {
    if (in_.substr(i_, 4) == "true") {
      i_ += 4;
      return true;
    }
    if (in_.substr(i_, 5) == "false") {
      i_ += 5;
      return false;
    }
    fail("expected boolean");
  }

  void parse_null() {
    if (in_.substr(i_, 4) != "null") fail("expected null");
    i_ += 4;
  }

  Json parse_number() {
    const std::size_t start = i_;
    if (peek() == '-') get();
    if (peek() == '0') {
      get();
    } else if (peek() >= '1' && peek() <= '9') {
      while (peek() >= '0' && peek() <= '9') get();
    } else {
      fail("expected number");
    }
    bool integral = true;
    if (peek() == '.') {
      integral = false;
      get();
      if (!(peek() >= '0' && peek() <= '9')) fail("expected fraction");
      while (peek() >= '0' && peek() <= '9') get();
    }
    if (peek() == 'e' || peek() == 'E') {
      integral = false;
      get();
      if (peek() == '+' || peek() == '-') get();
      if (!(peek() >= '0' && peek() <= '9')) fail("expected exponent");
      while (peek() >= '0' && peek() <= '9') get();
    }
    const std::string token(in_.substr(start, i_ - start));
    if (integral) {
      try {
        std::size_t used = 0;
        const long long value = std::stoll(token, &used, 10);
        if (used == token.size()) return Json::integer(static_cast<std::int64_t>(value));
      } catch (const std::exception&) {
      }
    }
    try {
      std::size_t used = 0;
      const double value = std::stod(token, &used);
      if (used != token.size() || !std::isfinite(value)) fail("bad number");
      return Json::real(value);
    } catch (const std::exception&) {
      fail("bad number");
    }
  }

  static void append_utf8(std::string& out, char32_t cp) {
    if (cp < 0x80) {
      out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
      out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
      out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
      out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
      out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
  }
};

void dump_string(std::ostream& os, const std::string& text) {
  os << '"';
  for (unsigned char c : text) {
    switch (c) {
      case '"':
        os << "\\\"";
        break;
      case '\\':
        os << "\\\\";
        break;
      case '\b':
        os << "\\b";
        break;
      case '\f':
        os << "\\f";
        break;
      case '\n':
        os << "\\n";
        break;
      case '\r':
        os << "\\r";
        break;
      case '\t':
        os << "\\t";
        break;
      default:
        if (c < 0x20) {
          static const char* hex = "0123456789abcdef";
          os << "\\u00" << hex[c >> 4] << hex[c & 0xF];
        } else {
          os << static_cast<char>(c);
        }
    }
  }
  os << '"';
}

std::string format_number(double value) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.16g", value);
  return buf;
}

void dump_into(std::ostream& os, const Json& json, int indent, int level) {
  switch (json.type) {
    case Json::Type::Null:
      os << "null";
      break;
    case Json::Type::Bool:
      os << (json.b ? "true" : "false");
      break;
    case Json::Type::Number:
      if (json.is_int)
        os << json.i64;
      else
        os << format_number(json.num);
      break;
    case Json::Type::String:
      dump_string(os, json.str);
      break;
    case Json::Type::Array: {
      os << '[';
      if (indent > 0 && !json.arr.empty()) os << '\n';
      for (std::size_t i = 0; i < json.arr.size(); ++i) {
        if (indent > 0) os << std::string(static_cast<std::size_t>(indent * (level + 1)), ' ');
        dump_into(os, json.arr[i], indent, level + 1);
        if (i + 1 != json.arr.size()) os << ',';
        if (indent > 0) os << '\n';
      }
      if (indent > 0 && !json.arr.empty())
        os << std::string(static_cast<std::size_t>(indent * level), ' ');
      os << ']';
      break;
    }
    case Json::Type::Object: {
      os << '{';
      if (indent > 0 && !json.obj.empty()) os << '\n';
      for (std::size_t i = 0; i < json.obj.size(); ++i) {
        if (indent > 0) os << std::string(static_cast<std::size_t>(indent * (level + 1)), ' ');
        dump_string(os, json.obj[i].first);
        os << (indent > 0 ? ": " : ":");
        dump_into(os, json.obj[i].second, indent, level + 1);
        if (i + 1 != json.obj.size()) os << ',';
        if (indent > 0) os << '\n';
      }
      if (indent > 0 && !json.obj.empty())
        os << std::string(static_cast<std::size_t>(indent * level), ' ');
      os << '}';
      break;
    }
  }
}

const std::string kEmpty;

}  // namespace

Json Json::nul() {
  return Json();
}

Json Json::boolean(bool value) {
  Json json;
  json.type = Type::Bool;
  json.b = value;
  return json;
}

Json Json::integer(std::int64_t value) {
  Json json;
  json.type = Type::Number;
  json.is_int = true;
  json.i64 = value;
  json.num = static_cast<double>(value);
  return json;
}

Json Json::real(double value) {
  Json json;
  json.type = Type::Number;
  json.num = value;
  json.i64 = static_cast<std::int64_t>(value);
  return json;
}

Json Json::string(std::string value) {
  Json json;
  json.type = Type::String;
  json.str = std::move(value);
  return json;
}

Json Json::array() {
  Json json;
  json.type = Type::Array;
  return json;
}

Json Json::object() {
  Json json;
  json.type = Type::Object;
  return json;
}

Json& Json::push(Json value) {
  arr.push_back(std::move(value));
  return arr.back();
}

Json& Json::set(const std::string& key, Json value) {
  for (auto& entry : obj) {
    if (entry.first == key) {
      entry.second = std::move(value);
      return entry.second;
    }
  }
  obj.emplace_back(key, std::move(value));
  return obj.back().second;
}

const Json* Json::find(const std::string& key) const {
  for (const auto& entry : obj) {
    if (entry.first == key) return &entry.second;
  }
  return nullptr;
}

Json* Json::find(const std::string& key) {
  for (auto& entry : obj) {
    if (entry.first == key) return &entry.second;
  }
  return nullptr;
}

bool Json::as_bool(bool fallback) const {
  return type == Type::Bool ? b : fallback;
}

double Json::as_number(double fallback) const {
  return type == Type::Number ? num : fallback;
}

std::int64_t Json::as_int(std::int64_t fallback) const {
  if (type != Type::Number) return fallback;
  if (is_int) return i64;
  return static_cast<std::int64_t>(num);
}

const std::string& Json::as_string() const {
  return type == Type::String ? str : kEmpty;
}

std::string Json::dump(int indent) const {
  std::ostringstream os;
  dump_into(os, *this, indent, 0);
  return os.str();
}

bool Json::parse(std::string_view in, Json& out, std::string& error) {
  Parser parser(in);
  return parser.parse(out, error);
}

}  // namespace fbv
