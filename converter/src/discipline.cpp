#include "discipline.hpp"

#include <cctype>
#include <string>
#include <unordered_map>
#include <utility>

namespace fbv {
namespace {

void append_lower(std::string& out, unsigned char c) {
  out.push_back(static_cast<char>(std::tolower(c)));
}

// ASCII plus Cyrillic А–Я / а–я. Other code points are copied unchanged.
std::string lower_utf8(const std::string& text) {
  std::string out;
  out.reserve(text.size());
  for (std::size_t i = 0; i < text.size();) {
    const auto b0 = static_cast<unsigned char>(text[i]);
    if (b0 < 0x80) {
      append_lower(out, b0);
      ++i;
      continue;
    }
    if (i + 1 < text.size() && b0 == 0xD0) {
      const auto b1 = static_cast<unsigned char>(text[i + 1]);
      if (b1 >= 0x90 && b1 <= 0x9F) {
        out.push_back(static_cast<char>(0xD0));
        out.push_back(static_cast<char>(b1 + 0x20));
        i += 2;
        continue;
      }
      if (b1 >= 0xA0 && b1 <= 0xAF) {
        out.push_back(static_cast<char>(0xD1));
        out.push_back(static_cast<char>(b1 - 0x20));
        i += 2;
        continue;
      }
    }
    out.push_back(text[i]);
    ++i;
  }
  return out;
}

std::string fold_class(std::string cls) {
  cls = lower_utf8(cls);
  if (cls.rfind("ifc", 0) == 0) cls.erase(0, 3);
  return cls;
}

const std::unordered_map<std::string, std::string>& class_disciplines() {
  static const std::unordered_map<std::string, std::string> table = {
      {"wall", "architecture"},
      {"wallstandardcase", "architecture"},
      {"slab", "architecture"},
      {"slabstandardcase", "architecture"},
      {"roof", "architecture"},
      {"covering", "architecture"},
      {"door", "architecture"},
      {"window", "architecture"},
      {"stair", "architecture"},
      {"stairflight", "architecture"},
      {"ramp", "architecture"},
      {"rampflight", "architecture"},
      {"railing", "architecture"},
      {"curtainwall", "architecture"},
      {"plate", "architecture"},
      {"chimney", "architecture"},
      {"shadingdevice", "architecture"},
      {"furniture", "architecture"},
      {"openingelement", "architecture"},
      {"beam", "structure"},
      {"column", "structure"},
      {"footing", "structure"},
      {"pile", "structure"},
      {"reinforcingbar", "structure"},
      {"reinforcingmesh", "structure"},
      {"tendon", "structure"},
      {"tendonanchor", "structure"},
      {"member", "structure"},
      {"ductsegment", "ventilation"},
      {"ductfitting", "ventilation"},
      {"airterminal", "ventilation"},
      {"airterminalbox", "ventilation"},
      {"fan", "ventilation"},
      {"damper", "ventilation"},
      {"coil", "ventilation"},
      {"airtoairheatrecovery", "ventilation"},
      {"humidifier", "ventilation"},
      {"evaporator", "ventilation"},
      {"evaporativecooler", "ventilation"},
      {"chiller", "ventilation"},
      {"coolingtower", "ventilation"},
      {"unitaryequipment", "ventilation"},
      {"boiler", "heating"},
      {"spaceheater", "heating"},
      {"burner", "heating"},
      {"tubebundle", "heating"},
      {"cablesegment", "electrical"},
      {"cablecarriersegment", "electrical"},
      {"cablecarrierfitting", "electrical"},
      {"cablefitting", "electrical"},
      {"junctionbox", "electrical"},
      {"outlet", "electrical"},
      {"lightfixture", "electrical"},
      {"lamp", "electrical"},
      {"switchingdevice", "electrical"},
      {"protectivedevice", "electrical"},
      {"electricdistributionboard", "electrical"},
      {"transformer", "electrical"},
      {"motorconnection", "electrical"},
      {"electricappliance", "electrical"},
      {"audiovisualappliance", "electrical"},
      {"communicationsappliance", "electrical"},
      {"pipesegment", "plumbing"},
      {"pipefitting", "plumbing"},
      {"sanitaryterminal", "plumbing"},
      {"wasteterminal", "plumbing"},
      {"stackterminal", "plumbing"},
      {"valve", "plumbing"},
      {"pump", "plumbing"},
      {"tank", "plumbing"},
      {"flowmeter", "plumbing"},
      {"interceptor", "plumbing"},
      {"firesuppressionterminal", "fire"},
      {"transportelement", "equipment"},
      {"discreteaccessory", "equipment"},
      {"fastener", "equipment"},
      {"mechanicalfastener", "equipment"},
  };
  return table;
}

// Longer needles first would be safer; these do not contain each other.
const std::pair<const char*, const char*> kTextRules[] = {
    {"вентиля", "ventilation"}, {"воздух", "ventilation"},  {"hvac", "ventilation"},
    {"отоп", "heating"},        {"heating", "heating"},     {"котел", "heating"},
    {"boiler", "heating"},      {"элект", "electrical"},    {"electric", "electrical"},
    {"освещ", "electrical"},    {"lighting", "electrical"}, {"кабел", "electrical"},
    {"cable", "electrical"},    {"сантех", "plumbing"},     {"водопров", "plumbing"},
    {"plumb", "plumbing"},      {"pipe", "plumbing"},       {"пожар", "fire"},
    {"fire", "fire"},           {"архит", "architecture"},  {"architect", "architecture"},
    {"конструк", "structure"},  {"structure", "structure"}, {"каркас", "structure"},
    {"оборуд", "equipment"},    {"equipment", "equipment"},
};

std::string discipline_from_text(const std::string& text) {
  const std::string folded = lower_utf8(text);
  for (const auto& rule : kTextRules) {
    if (folded.find(rule.first) != std::string::npos) return rule.second;
  }
  return {};
}

}  // namespace

std::string assign_discipline(const std::string& ifc_class,
                              const std::vector<std::string>& system_texts) {
  for (const std::string& text : system_texts) {
    const std::string from_system = discipline_from_text(text);
    if (!from_system.empty()) return from_system;
  }
  const auto it = class_disciplines().find(fold_class(ifc_class));
  if (it == class_disciplines().end()) return {};
  return it->second;
}

}  // namespace fbv
