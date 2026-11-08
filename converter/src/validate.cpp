#include "fbv/convert.hpp"

#include "fbv/glb.hpp"
#include "fbv/io.hpp"
#include "fbv/json.hpp"
#include "fbv/sha256.hpp"
#include "fbv/sqlite_util.hpp"
#include "fbv/zip.hpp"
#include "fbv_version.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <map>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <set>
#include <sstream>
#include <string>

namespace fbv {
namespace {

struct TempDir {
  std::filesystem::path path;
  ~TempDir() {
    if (!path.empty()) {
      std::error_code ec;
      std::filesystem::remove_all(path, ec);
    }
  }
};

std::filesystem::path make_temp_dir() {
  const auto base = std::filesystem::temp_directory_path();
  for (int i = 0; i < 1000; ++i) {
    auto path =
        base / ("fbvval-" + std::to_string(i) + "-" +
                std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    if (std::filesystem::create_directory(path)) return path;
  }
  throw std::runtime_error("cannot create a temporary directory");
}

const Json* field(const Json& json, const char* key) {
  return json.type == Json::Type::Object ? json.find(key) : nullptr;
}

bool near(double a, double b) {
  return std::abs(a - b) < 1e-5;
}

}  // namespace

int validate_package(const std::string& path, std::string& report) {
  std::vector<std::string> errors;
  try {
    const std::filesystem::path input(path);
    TempDir temp;
    std::filesystem::path root = input;
    if (std::filesystem::is_regular_file(input)) {
      temp.path = make_temp_dir();
      std::string unzip_error;
      if (!unzip_stored(input, temp.path, unzip_error)) errors.push_back(unzip_error);
      root = temp.path;
    } else if (!std::filesystem::is_directory(input)) {
      errors.push_back("package path does not exist");
    }
    if (errors.empty()) {
      Json manifest;
      std::string parse_error;
      if (!Json::parse(read_text(root / "manifest.json"), manifest, parse_error)) {
        errors.push_back(parse_error);
      } else if (field(manifest, "format_version") == nullptr ||
                 field(manifest, "format_version")->as_int(-1) < FBV_FORMAT_VERSION_MIN ||
                 field(manifest, "format_version")->as_int(-1) > FBV_FORMAT_VERSION) {
        errors.push_back("unsupported format_version");
      } else {
        const auto format_version = field(manifest, "format_version")->as_int(-1);
        const Json* parts = field(manifest, "parts");
        if (parts == nullptr || parts->type != Json::Type::Object) {
          errors.push_back("manifest.parts is missing");
        } else {
          for (const auto& entry : parts->obj) {
            const auto file = root / std::filesystem::path(entry.first);
            if (!std::filesystem::is_regular_file(file)) {
              errors.push_back("missing part " + entry.first);
              continue;
            }
            const Json* hash = field(entry.second, "sha256");
            if (hash == nullptr || sha256_file(file) != hash->as_string()) {
              errors.push_back("sha256 mismatch for " + entry.first);
            }
            if (const Json* bytes = field(entry.second, "bytes")) {
              if (static_cast<std::int64_t>(std::filesystem::file_size(file)) !=
                  bytes->as_int(-1)) {
                errors.push_back("size mismatch for " + entry.first);
              }
            }
          }
        }
        const std::string codec =
            field(manifest, "brep") && field(*field(manifest, "brep"), "codec")
                ? field(*field(manifest, "brep"), "codec")->as_string()
                : std::string();
        SqliteDb db(root / "meta.sqlite", false);
        auto meta = db.prepare("SELECT value FROM schema_meta WHERE key = 'format_version'");
        if (!meta.step_row() || meta.column_text(0) != std::to_string(format_version)) {
          errors.push_back("meta.sqlite schema_meta does not match format_version");
        }
        if (format_version >= 2) {
          auto systems = db.prepare(
              "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'systems'");
          auto members = db.prepare(
              "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'system_elements'");
          if (!systems.step_row() || !members.step_row()) {
            errors.push_back("format_version 2 is missing table systems or system_elements");
          }
        }
        auto count_elements = db.prepare("SELECT COUNT(*) FROM elements");
        count_elements.step_row();
        const int element_count = static_cast<int>(count_elements.column_int64(0));
        auto count_spatial = db.prepare("SELECT COUNT(*) FROM spatial");
        count_spatial.step_row();
        const int spatial_count = static_cast<int>(count_spatial.column_int64(0));
        auto count_mesh = db.prepare("SELECT COUNT(*) FROM elements WHERE mesh_node IS NOT NULL");
        count_mesh.step_row();
        const int mesh_count = static_cast<int>(count_mesh.column_int64(0));
        if (const Json* counts = field(manifest, "counts")) {
          if (field(*counts, "elements") &&
              field(*counts, "elements")->as_int(-1) != element_count) {
            errors.push_back("manifest element count does not match meta.sqlite");
          }
          if (field(*counts, "elements_with_mesh") &&
              field(*counts, "elements_with_mesh")->as_int(-1) != mesh_count) {
            errors.push_back("manifest mesh count does not match meta.sqlite");
          }
          if (field(*counts, "spatial") && field(*counts, "spatial")->as_int(-1) != spatial_count) {
            errors.push_back("manifest spatial count does not match meta.sqlite");
          }
        } else {
          errors.push_back("manifest.counts is missing");
        }
        auto fts = db.prepare("SELECT COUNT(*) FROM fts_elements");
        if (!fts.step_row() || fts.column_int64(0) != element_count) {
          errors.push_back("fts_elements does not contain every element");
        }
        GlbContents lod0;
        std::string glb_error;
        if (!read_glb(root / "mesh" / "lod0.glb", lod0, glb_error)) {
          errors.push_back(glb_error);
        }
        const auto lod_id_list = glb_element_ids(lod0);
        const std::set<std::int64_t> lod_ids(lod_id_list.begin(), lod_id_list.end());
        std::set<std::string> guids;
        auto elements = db.prepare(
            "SELECT id, guid, mesh_node, brep_ref, bbox_min_x, bbox_min_y, bbox_min_z, bbox_max_x, "
            "bbox_max_y, bbox_max_z FROM elements ORDER BY id");
        while (elements.step_row()) {
          const auto id = elements.column_int64(0);
          const std::string guid = elements.column_text(1);
          if (guid.empty())
            errors.push_back("element " + std::to_string(id) + " has an empty guid");
          if (!guids.insert(guid).second) errors.push_back("duplicate guid " + guid);
          const bool has_mesh = !elements.column_is_null(2);
          const auto element_glb = root / "mesh" / "elements" / (std::to_string(id) + ".glb");
          if (has_mesh) {
            if (!lod_ids.count(id)) {
              errors.push_back("lod0.glb is missing element " + std::to_string(id));
            }
            if (!std::filesystem::is_regular_file(element_glb)) {
              errors.push_back("missing per-element glb for " + std::to_string(id));
            } else {
              GlbContents one;
              if (!read_glb(element_glb, one, glb_error))
                errors.push_back(glb_error);
              else {
                const auto ids = glb_element_ids(one);
                if (ids.size() != 1 || ids[0] != id) {
                  errors.push_back("per-element glb extras.elementId mismatch for " +
                                   std::to_string(id));
                }
              }
            }
          }
          if (codec == "analytic-box-v1" && elements.column_is_null(3) && has_mesh) {
            errors.push_back("meshed element " + std::to_string(id) + " has no brep_ref");
          }
          if (codec == "none" && !elements.column_is_null(3)) {
            errors.push_back("brep_ref is set while brep codec is none");
          }
        }
        if (codec == "analytic-box-v1") {
          std::map<std::int64_t, std::array<double, 6>> boxes;
          auto boxed = db.prepare(
              "SELECT id, bbox_min_x, bbox_min_y, bbox_min_z, bbox_max_x, bbox_max_y, bbox_max_z "
              "FROM elements WHERE brep_ref IS NOT NULL");
          while (boxed.step_row()) {
            boxes[boxed.column_int64(0)] = {boxed.column_double(1), boxed.column_double(2),
                                            boxed.column_double(3), boxed.column_double(4),
                                            boxed.column_double(5), boxed.column_double(6)};
          }
          const auto index = read_binary(root / "brep.index");
          const auto pack = read_binary(root / "brep.pack");
          if (index.size() < 12 || std::memcmp(index.data(), "FBVI", 4) != 0) {
            errors.push_back("brep.index magic mismatch");
          } else if (pack.size() < 12 || std::memcmp(pack.data(), "FBVB", 4) != 0) {
            errors.push_back("brep.pack magic mismatch");
          } else {
            const auto read_u32 = [](const std::uint8_t* p) {
              return static_cast<std::uint32_t>(p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24));
            };
            const auto read_u64 = [](const std::uint8_t* p) {
              std::uint64_t value = 0;
              for (int i = 0; i < 8; ++i) value |= static_cast<std::uint64_t>(p[i]) << (8 * i);
              return value;
            };
            const auto read_f64 = [](const std::uint8_t* p) {
              double value = 0;
              std::memcpy(&value, p, sizeof(value));
              return value;
            };
            const std::uint32_t count = read_u32(index.data() + 8);
            constexpr std::size_t kRecord = 8 + 8 + 8 + 4 + 8 * 12;
            if (count != boxes.size())
              errors.push_back("brep.index count does not match brep_ref rows");
            if (12 + static_cast<std::size_t>(count) * kRecord > index.size()) {
              errors.push_back("brep.index is truncated");
            } else {
              for (std::uint32_t i = 0; i < count; ++i) {
                const std::uint8_t* rec = index.data() + 12 + static_cast<std::size_t>(i) * kRecord;
                const auto id = static_cast<std::int64_t>(read_u64(rec));
                const auto offset = read_u64(rec + 8);
                const auto length = read_u64(rec + 16);
                const auto found = boxes.find(id);
                if (found == boxes.end()) {
                  errors.push_back("brep.index references unknown element " + std::to_string(id));
                  continue;
                }
                if (offset + length > pack.size() || length < 52) {
                  errors.push_back("brep record is out of range");
                  continue;
                }
                const std::uint8_t* body = pack.data() + offset;
                double actual[6];
                for (int axis = 0; axis < 3; ++axis) actual[axis] = read_f64(body + 4 + axis * 8);
                for (int axis = 0; axis < 3; ++axis)
                  actual[axis + 3] = read_f64(body + 28 + axis * 8);
                for (int axis = 0; axis < 6; ++axis) {
                  if (!near(actual[axis], found->second[static_cast<std::size_t>(axis)])) {
                    errors.push_back("brep box does not match sqlite bbox for element " +
                                     std::to_string(id));
                    break;
                  }
                }
              }
            }
          }
        } else if (codec != "none" && !codec.empty()) {
          errors.push_back("unsupported brep codec " + codec);
        }
      }
    }
  } catch (const std::exception& ex) {
    errors.push_back(ex.what());
  }
  if (errors.empty()) {
    report = "OK\n";
    return 0;
  }
  std::ostringstream out;
  for (const std::string& error : errors) out << error << '\n';
  report = out.str();
  return 3;
}

}  // namespace fbv
