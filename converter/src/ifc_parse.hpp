#pragma once

#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace fbv {

struct IfcValue {
  enum class Kind { Null, Derived, Integer, Real, String, Enum, Ref, List, Typed };
  Kind kind = Kind::Null;
  std::int64_t i = 0;
  double real = 0;
  std::string text;
  std::vector<IfcValue> items;
};

struct IfcEntity {
  std::int64_t id = 0;
  std::string type;
  std::vector<IfcValue> attrs;
};

struct IfcFile {
  std::string schema;
  std::map<std::int64_t, IfcEntity> entities;
  std::unordered_map<std::string, std::vector<std::int64_t>> by_type;

  const IfcEntity* find(std::int64_t id) const;
  std::vector<const IfcEntity*> typed(const std::string& type) const;
};

struct IfcParseError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

std::string decode_ifc_string(std::string_view raw);
IfcFile parse_ifc(std::string_view text);

}  // namespace fbv
