#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace fbv {

struct Json {
  enum class Type { Null, Bool, Number, String, Array, Object };

  Type type = Type::Null;
  bool b = false;
  double num = 0;
  std::int64_t i64 = 0;
  bool is_int = false;
  std::string str;
  std::vector<Json> arr;
  std::vector<std::pair<std::string, Json>> obj;

  static Json nul();
  static Json boolean(bool value);
  static Json integer(std::int64_t value);
  static Json real(double value);
  static Json string(std::string value);
  static Json array();
  static Json object();

  Json& push(Json value);
  Json& set(const std::string& key, Json value);
  const Json* find(const std::string& key) const;
  Json* find(const std::string& key);

  bool as_bool(bool fallback = false) const;
  double as_number(double fallback = 0) const;
  std::int64_t as_int(std::int64_t fallback = 0) const;
  const std::string& as_string() const;

  std::string dump(int indent = 2) const;

  static bool parse(std::string_view in, Json& out, std::string& error);
};

}  // namespace fbv
