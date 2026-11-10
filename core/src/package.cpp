#include "package.hpp"

#include "fbv/io.hpp"
#include "fbv_version.h"
#include "fbv/sha256.hpp"
#include "fbv/zip.hpp"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <set>
#include <string>

namespace fbv {

OwnedTempDir::~OwnedTempDir() {
  if (!path.empty()) {
    std::error_code ec;
    std::filesystem::remove_all(path, ec);
  }
}

std::filesystem::path make_temp_dir() {
  const auto base = std::filesystem::temp_directory_path();
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  for (int i = 0; i < 1000; ++i) {
    auto path = base / ("fbvpkg-" + std::to_string(stamp) + "-" + std::to_string(i));
    if (std::filesystem::create_directory(path)) return path;
  }
  throw std::runtime_error("cannot create a temporary directory");
}

void copy_str(char* dest, std::size_t size, const std::string& text) {
  if (dest == nullptr || size == 0) return;
  std::snprintf(dest, size, "%s", text.c_str());
}

const Json* field(const Json& json, const char* key) {
  if (json.type != Json::Type::Object) return nullptr;
  return json.find(key);
}

bool read_vec3(const Json* array, double out[3]) {
  if (array == nullptr || array->type != Json::Type::Array || array->arr.size() < 3) return false;
  out[0] = array->arr[0].as_number();
  out[1] = array->arr[1].as_number();
  out[2] = array->arr[2].as_number();
  return true;
}

std::uint32_t read_u32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24));
}

std::uint64_t read_u64(const std::uint8_t* p) {
  std::uint64_t value = 0;
  for (int i = 0; i < 8; ++i) value |= static_cast<std::uint64_t>(p[i]) << (8 * i);
  return value;
}

double read_f64(const std::uint8_t* p) {
  double value = 0;
  std::memcpy(&value, p, sizeof(value));
  return value;
}

std::string like_pattern(const std::string& query) {
  std::string out = "%";
  for (char c : query) {
    if (c == '\\' || c == '%' || c == '_') out.push_back('\\');
    out.push_back(c);
  }
  out.push_back('%');
  return out;
}

std::string fts_query(const std::string& query) {
  std::string out = "\"";
  for (char c : query) {
    if (c == '"')
      out += "\"\"";
    else
      out.push_back(c);
  }
  out += "\"*";
  return out;
}

}  // namespace fbv

fbv_package::~fbv_package() {
  delete temp;
}

int fbv_package::fill_element(fbv::Stmt& stmt, fbv_element_info* out) {
  std::memset(out, 0, sizeof(*out));
  out->id = stmt.column_int64(0);
  out->storey_id = stmt.column_is_null(1) ? 0 : stmt.column_int64(1);
  out->parent_id = stmt.column_is_null(2) ? 0 : stmt.column_int64(2);
  out->type_id = stmt.column_is_null(3) ? 0 : stmt.column_int64(3);
  out->mesh_node = stmt.column_is_null(4) ? -1 : static_cast<int32_t>(stmt.column_int64(4));
  out->has_brep = stmt.column_is_null(5) ? 0 : 1;
  out->has_bbox = stmt.column_is_null(6) ? 0 : 1;
  if (out->has_bbox) {
    out->bbox_min[0] = stmt.column_double(6);
    out->bbox_min[1] = stmt.column_double(7);
    out->bbox_min[2] = stmt.column_double(8);
    out->bbox_max[0] = stmt.column_double(9);
    out->bbox_max[1] = stmt.column_double(10);
    out->bbox_max[2] = stmt.column_double(11);
  }
  out->color[0] = static_cast<float>(stmt.column_double(12));
  out->color[1] = static_cast<float>(stmt.column_double(13));
  out->color[2] = static_cast<float>(stmt.column_double(14));
  fbv::copy_str(out->guid, sizeof(out->guid), stmt.column_text(15));
  fbv::copy_str(out->ifc_class, sizeof(out->ifc_class), stmt.column_text(16));
  fbv::copy_str(out->name, sizeof(out->name), stmt.column_text(17));
  fbv::copy_str(out->tag, sizeof(out->tag), stmt.column_text(18));
  fbv::copy_str(out->type_name, sizeof(out->type_name), stmt.column_text(19));
  fbv::copy_str(out->material, sizeof(out->material), stmt.column_text(20));
  return FBV_OK;
}

int fbv_package::manifest_info(fbv_manifest_info* out) const {
  std::memset(out, 0, sizeof(*out));
  out->format_version = static_cast<int32_t>(manifest.as_int(0));
  if (const fbv::Json* version = fbv::field(manifest, "format_version")) {
    out->format_version = static_cast<int32_t>(version->as_int(0));
  }
  fbv::copy_str(out->name, sizeof(out->name),
                fbv::field(manifest, "name") != nullptr ? fbv::field(manifest, "name")->as_string()
                                                        : std::string());
  if (const fbv::Json* source = fbv::field(manifest, "source")) {
    if (const fbv::Json* file = fbv::field(*source, "filename"))
      fbv::copy_str(out->source_file, sizeof(out->source_file), file->as_string());
    if (const fbv::Json* schema = fbv::field(*source, "schema"))
      fbv::copy_str(out->source_schema, sizeof(out->source_schema), schema->as_string());
  }
  if (const fbv::Json* units = fbv::field(manifest, "units")) {
    if (const fbv::Json* unit = fbv::field(*units, "source_length_unit"))
      fbv::copy_str(out->length_unit, sizeof(out->length_unit), unit->as_string());
  }
  if (const fbv::Json* brep = fbv::field(manifest, "brep")) {
    if (const fbv::Json* codec = fbv::field(*brep, "codec"))
      fbv::copy_str(out->brep_codec, sizeof(out->brep_codec), codec->as_string());
  }
  fbv::read_vec3(fbv::field(manifest, "local_origin"), out->local_origin);
  if (const fbv::Json* bbox = fbv::field(manifest, "world_bbox")) {
    fbv::read_vec3(fbv::field(*bbox, "min"), out->world_min);
    fbv::read_vec3(fbv::field(*bbox, "max"), out->world_max);
  }
  if (const fbv::Json* counts = fbv::field(manifest, "counts")) {
    if (const fbv::Json* n = fbv::field(*counts, "elements"))
      out->element_count = static_cast<int32_t>(n->as_int(0));
    if (const fbv::Json* n = fbv::field(*counts, "elements_with_mesh"))
      out->mesh_element_count = static_cast<int32_t>(n->as_int(0));
    if (const fbv::Json* n = fbv::field(*counts, "spatial"))
      out->spatial_count = static_cast<int32_t>(n->as_int(0));
    if (const fbv::Json* n = fbv::field(*counts, "warnings"))
      out->warning_count = static_cast<int32_t>(n->as_int(0));
  }
  return FBV_OK;
}

int fbv_package::spatial_count() {
  try {
    auto stmt = db.prepare("SELECT COUNT(*) FROM spatial");
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

int fbv_package::spatial_at(int index, fbv_spatial_info* out) {
  try {
    auto stmt = db.prepare(
        "SELECT id, parent_id, elevation, kind, COALESCE(name,'') FROM spatial ORDER BY id LIMIT 1 "
        "OFFSET ?");
    stmt.bind_int64(1, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    std::memset(out, 0, sizeof(*out));
    out->id = stmt.column_int64(0);
    out->parent_id = stmt.column_is_null(1) ? 0 : stmt.column_int64(1);
    out->has_elevation = stmt.column_is_null(2) ? 0 : 1;
    out->elevation = out->has_elevation ? stmt.column_double(2) : 0;
    fbv::copy_str(out->kind, sizeof(out->kind), stmt.column_text(3));
    fbv::copy_str(out->name, sizeof(out->name), stmt.column_text(4));
    auto kids = db.prepare("SELECT COUNT(*) FROM elements WHERE parent_id = ?");
    kids.bind_int64(1, out->id);
    if (kids.step_row()) out->child_count = static_cast<int32_t>(kids.column_int64(0));
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::element_count() {
  try {
    auto stmt = db.prepare("SELECT COUNT(*) FROM elements");
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

namespace {

constexpr const char* kElementSelect =
    "SELECT e.id, e.storey_id, e.parent_id, e.type_id, e.mesh_node, e.brep_ref, "
    "e.bbox_min_x, e.bbox_min_y, e.bbox_min_z, e.bbox_max_x, e.bbox_max_y, e.bbox_max_z, "
    "COALESCE(e.color_r,0.7), COALESCE(e.color_g,0.7), COALESCE(e.color_b,0.7), "
    "e.guid, e.ifc_class, COALESCE(e.name,''), COALESCE(e.tag,''), COALESCE(t.name,''), "
    "COALESCE((SELECT m.name FROM material_layers ml JOIN materials m ON m.id = ml.material_id "
    "WHERE ml.set_id = e.material_set_id ORDER BY ml.layer_order LIMIT 1), '') "
    "FROM elements e LEFT JOIN types t ON t.id = e.type_id ";

}  // namespace

int fbv_package::element_at(int index, fbv_element_info* out) {
  try {
    const std::string sql = std::string(kElementSelect) + "ORDER BY e.id LIMIT 1 OFFSET ?";
    auto stmt = db.prepare(sql.c_str());
    stmt.bind_int64(1, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    return fill_element(stmt, out);
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::element_by_id(std::int64_t id, fbv_element_info* out) {
  try {
    const std::string sql = std::string(kElementSelect) + "WHERE e.id = ?";
    auto stmt = db.prepare(sql.c_str());
    stmt.bind_int64(1, id);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    return fill_element(stmt, out);
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::prop_count(std::int64_t element_id) {
  try {
    auto stmt = db.prepare(
        "SELECT COUNT(*) FROM psets p JOIN props pr ON pr.pset_id = p.id "
        "WHERE p.element_id = ?1 OR p.type_id = (SELECT type_id FROM elements WHERE id = ?1)");
    stmt.bind_int64(1, element_id);
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

int fbv_package::prop_at(std::int64_t element_id, int index, fbv_prop* out) {
  try {
    auto stmt = db.prepare(
        "SELECT p.name, pr.name, COALESCE(pr.value_text,''), pr.value_num, COALESCE(pr.unit,''), "
        "COALESCE(pr.data_type,''), p.source "
        "FROM psets p JOIN props pr ON pr.pset_id = p.id "
        "WHERE p.element_id = ?1 OR p.type_id = (SELECT type_id FROM elements WHERE id = ?1) "
        "ORDER BY p.id, pr.id LIMIT 1 OFFSET ?2");
    stmt.bind_int64(1, element_id);
    stmt.bind_int64(2, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    std::memset(out, 0, sizeof(*out));
    fbv::copy_str(out->pset, sizeof(out->pset), stmt.column_text(0));
    fbv::copy_str(out->name, sizeof(out->name), stmt.column_text(1));
    fbv::copy_str(out->value_text, sizeof(out->value_text), stmt.column_text(2));
    out->has_num = stmt.column_is_null(3) ? 0 : 1;
    out->value_num = out->has_num ? stmt.column_double(3) : 0;
    fbv::copy_str(out->unit, sizeof(out->unit), stmt.column_text(4));
    fbv::copy_str(out->data_type, sizeof(out->data_type), stmt.column_text(5));
    fbv::copy_str(out->source, sizeof(out->source), stmt.column_text(6));
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::quantity_count(std::int64_t element_id) {
  try {
    auto stmt = db.prepare("SELECT COUNT(*) FROM quantities WHERE element_id = ?");
    stmt.bind_int64(1, element_id);
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

int fbv_package::quantity_at(std::int64_t element_id, int index, fbv_quantity* out) {
  try {
    auto stmt = db.prepare(
        "SELECT COALESCE(qset,''), name, kind, COALESCE(unit,''), value FROM quantities "
        "WHERE element_id = ? ORDER BY id LIMIT 1 OFFSET ?");
    stmt.bind_int64(1, element_id);
    stmt.bind_int64(2, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    std::memset(out, 0, sizeof(*out));
    fbv::copy_str(out->qset, sizeof(out->qset), stmt.column_text(0));
    fbv::copy_str(out->name, sizeof(out->name), stmt.column_text(1));
    fbv::copy_str(out->kind, sizeof(out->kind), stmt.column_text(2));
    fbv::copy_str(out->unit, sizeof(out->unit), stmt.column_text(3));
    out->value = stmt.column_double(4);
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::classification_count(std::int64_t element_id) {
  try {
    auto stmt = db.prepare("SELECT COUNT(*) FROM classification WHERE element_id = ?");
    stmt.bind_int64(1, element_id);
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

int fbv_package::classification_at(std::int64_t element_id, int index, fbv_classification* out) {
  try {
    auto stmt = db.prepare(
        "SELECT COALESCE(system,''), COALESCE(code,''), COALESCE(title,'') FROM classification "
        "WHERE element_id = ? ORDER BY id LIMIT 1 OFFSET ?");
    stmt.bind_int64(1, element_id);
    stmt.bind_int64(2, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    std::memset(out, 0, sizeof(*out));
    fbv::copy_str(out->system_name, sizeof(out->system_name), stmt.column_text(0));
    fbv::copy_str(out->code, sizeof(out->code), stmt.column_text(1));
    fbv::copy_str(out->title, sizeof(out->title), stmt.column_text(2));
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::world_aabb(std::int64_t element_id, double min_xyz[3], double max_xyz[3]) const {
  for (const auto& box : brep_boxes) {
    if (box.element_id == element_id) {
      std::memcpy(min_xyz, box.min_xyz, sizeof(box.min_xyz));
      std::memcpy(max_xyz, box.max_xyz, sizeof(box.max_xyz));
      return FBV_OK;
    }
  }
  set_error("element has no analytic B-Rep box");
  return FBV_ERR;
}

int fbv_package::search(const char* query, std::int64_t* ids, int cap, int* total) {
  if (query == nullptr || query[0] == '\0') {
    if (total != nullptr) *total = 0;
    return FBV_OK;
  }
  try {
    std::set<std::int64_t> found;
    const std::string pattern = fbv::like_pattern(query);
    auto like = db.prepare(
        "SELECT id FROM elements WHERE name LIKE ?1 ESCAPE '\\' OR tag LIKE ?1 ESCAPE '\\' "
        "OR guid LIKE ?1 ESCAPE '\\' OR ifc_class LIKE ?1 ESCAPE '\\'");
    like.bind_text(1, pattern);
    while (like.step_row()) found.insert(like.column_int64(0));
    try {
      auto fts = db.prepare("SELECT element_id FROM fts_elements WHERE fts_elements MATCH ?");
      fts.bind_text(1, fbv::fts_query(query));
      while (fts.step_row()) found.insert(fts.column_int64(0));
    } catch (const fbv::SqliteError&) {
    }
    if (total != nullptr) *total = static_cast<int>(found.size());
    int written = 0;
    if (ids != nullptr && cap > 0) {
      for (std::int64_t id : found) {
        if (written >= cap) break;
        ids[written++] = id;
      }
    }
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

int fbv_package::spec_count() {
  try {
    auto stmt = db.prepare("SELECT COUNT(*) FROM spec_views");
    if (!stmt.step_row()) return 0;
    return static_cast<int>(stmt.column_int64(0));
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return -1;
  }
}

int fbv_package::spec_at(int index, fbv_spec_row* out) {
  try {
    auto stmt = db.prepare(
        "SELECT s.storey_id, s.element_count, s.quantity_kind, s.quantity_sum, "
        "COALESCE(s.ifc_class,''), COALESCE(s.type_name,''), COALESCE(s.material_name,''), "
        "COALESCE(sp.name,'') "
        "FROM spec_views s LEFT JOIN spatial sp ON sp.id = s.storey_id ORDER BY s.id LIMIT 1 "
        "OFFSET ?");
    stmt.bind_int64(1, index);
    if (!stmt.step_row()) return FBV_ERR_RANGE;
    std::memset(out, 0, sizeof(*out));
    out->storey_id = stmt.column_is_null(0) ? 0 : stmt.column_int64(0);
    out->element_count = static_cast<int32_t>(stmt.column_int64(1));
    out->has_quantity = stmt.column_is_null(2) ? 0 : 1;
    out->quantity_sum = out->has_quantity ? stmt.column_double(3) : 0;
    fbv::copy_str(out->ifc_class, sizeof(out->ifc_class), stmt.column_text(4));
    fbv::copy_str(out->type_name, sizeof(out->type_name), stmt.column_text(5));
    fbv::copy_str(out->material_name, sizeof(out->material_name), stmt.column_text(6));
    if (out->has_quantity)
      fbv::copy_str(out->quantity_kind, sizeof(out->quantity_kind), stmt.column_text(2));
    fbv::copy_str(out->storey_name, sizeof(out->storey_name), stmt.column_text(7));
    return FBV_OK;
  } catch (const std::exception& ex) {
    set_error(ex.what());
    return FBV_ERR;
  }
}

namespace {

bool load_brep(fbv_package& package, std::string& error) {
  const auto pack_path = package.root / "brep.pack";
  const auto index_path = package.root / "brep.index";
  if (!std::filesystem::is_regular_file(pack_path) ||
      !std::filesystem::is_regular_file(index_path)) {
    error = "brep.pack or brep.index is missing";
    return false;
  }
  const auto index = fbv::read_binary(index_path);
  const auto pack = fbv::read_binary(pack_path);
  if (index.size() < 12 || std::memcmp(index.data(), "FBVI", 4) != 0) {
    error = "brep.index magic mismatch";
    return false;
  }
  if (pack.size() < 12 || std::memcmp(pack.data(), "FBVB", 4) != 0) {
    error = "brep.pack magic mismatch";
    return false;
  }
  const auto count = fbv::read_u32(index.data() + 8);
  constexpr std::size_t kRecord = 8 + 8 + 8 + 4 + 8 * 12;
  if (12 + static_cast<std::size_t>(count) * kRecord > index.size()) {
    error = "brep.index is truncated";
    return false;
  }
  package.brep_boxes.clear();
  package.brep_boxes.reserve(count);
  for (std::uint32_t i = 0; i < count; ++i) {
    const std::uint8_t* rec = index.data() + 12 + static_cast<std::size_t>(i) * kRecord;
    const auto element_id = static_cast<std::int64_t>(fbv::read_u64(rec));
    const auto offset = fbv::read_u64(rec + 8);
    const auto length = fbv::read_u64(rec + 16);
    if (offset + length > pack.size() || length < 4 + 48) {
      error = "brep record is out of range";
      return false;
    }
    const std::uint8_t* body = pack.data() + offset;
    if (fbv::read_u32(body) != 1) {
      error = "unsupported analytic brep kind";
      return false;
    }
    fbv::BrepBox box;
    box.element_id = element_id;
    for (int axis = 0; axis < 3; ++axis) box.min_xyz[axis] = fbv::read_f64(body + 4 + axis * 8);
    for (int axis = 0; axis < 3; ++axis) box.max_xyz[axis] = fbv::read_f64(body + 28 + axis * 8);
    package.brep_boxes.push_back(box);
  }
  return true;
}

bool verify_parts(const fbv_package& package, std::string& error) {
  const fbv::Json* parts = fbv::field(package.manifest, "parts");
  if (parts == nullptr || parts->type != fbv::Json::Type::Object) {
    error = "manifest.parts is missing";
    return false;
  }
  for (const auto& entry : parts->obj) {
    const auto path = package.root / std::filesystem::path(entry.first);
    if (!std::filesystem::is_regular_file(path)) {
      error = "missing part " + entry.first;
      return false;
    }
    const fbv::Json* hash = fbv::field(entry.second, "sha256");
    if (hash == nullptr || hash->as_string().empty()) {
      error = "part has no sha256: " + entry.first;
      return false;
    }
    const std::string actual = fbv::sha256_file(path);
    if (actual != hash->as_string()) {
      error = "sha256 mismatch for " + entry.first;
      return false;
    }
    if (const fbv::Json* bytes = fbv::field(entry.second, "bytes")) {
      const auto size = std::filesystem::file_size(path);
      if (static_cast<std::int64_t>(size) != bytes->as_int(-1)) {
        error = "size mismatch for " + entry.first;
        return false;
      }
    }
  }
  return true;
}

}  // namespace

fbv_package* fbv_package_open_impl(const char* path, std::string& error) {
  if (path == nullptr || path[0] == '\0') {
    error = "path is empty";
    return nullptr;
  }
  auto package = std::make_unique<fbv_package>();
  const std::filesystem::path input(path);
  std::error_code ec;
  if (std::filesystem::is_directory(input, ec)) {
    package->root = input;
  } else if (std::filesystem::is_regular_file(input, ec)) {
    auto* temp = new fbv::OwnedTempDir();
    temp->path = fbv::make_temp_dir();
    package->temp = temp;
    package->root = temp->path;
    if (!fbv::unzip_stored(input, package->root, error)) return nullptr;
  } else {
    error = "package path does not exist";
    return nullptr;
  }
  std::string manifest_text;
  try {
    manifest_text = fbv::read_text(package->root / "manifest.json");
  } catch (const std::exception& ex) {
    error = ex.what();
    return nullptr;
  }
  if (!fbv::Json::parse(manifest_text, package->manifest, error)) return nullptr;
  const fbv::Json* version = fbv::field(package->manifest, "format_version");
  const auto format_version = version == nullptr ? std::int64_t{-1} : version->as_int(-1);
  if (format_version < FBV_FORMAT_VERSION_MIN || format_version > FBV_FORMAT_VERSION) {
    error = "unsupported format_version";
    return nullptr;
  }
  if (!verify_parts(*package, error)) return nullptr;
  try {
    package->db.open(package->root / "meta.sqlite", false);
    auto meta = package->db.prepare("SELECT value FROM schema_meta WHERE key = 'format_version'");
    if (!meta.step_row() || meta.column_text(0) != std::to_string(format_version)) {
      error = "meta.sqlite schema_meta format_version does not match the manifest";
      return nullptr;
    }
    if (format_version >= 2) {
      auto systems = package->db.prepare(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'systems'");
      auto members = package->db.prepare(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'system_elements'");
      if (!systems.step_row() || !members.step_row()) {
        error = "format_version " + std::to_string(format_version) +
                " is missing table systems or system_elements";
        return nullptr;
      }
    }
    if (format_version >= 3) {
      auto tiles = package->db.prepare(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'tiles'");
      auto tile_elements = package->db.prepare(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'tile_elements'");
      if (!tiles.step_row() || !tile_elements.step_row()) {
        error = "format_version " + std::to_string(format_version) +
                " is missing table tiles or tile_elements";
        return nullptr;
      }
    }
    if (format_version >= 4) {
      auto exact = package->db.prepare(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'exact_geometry'");
      if (!exact.step_row()) {
        error =
            "format_version " + std::to_string(format_version) + " is missing table exact_geometry";
        return nullptr;
      }
      auto rows = package->db.prepare("SELECT path, bytes FROM exact_geometry");
      while (rows.step_row()) {
        const std::string rel = rows.column_text(0);
        if (rel.empty() || rel.find("..") != std::string::npos) {
          error = "exact_geometry path is not inside the package";
          return nullptr;
        }
        const auto file = package->root / std::filesystem::path(rel);
        if (!std::filesystem::is_regular_file(file) ||
            static_cast<std::int64_t>(std::filesystem::file_size(file)) != rows.column_int64(1)) {
          error = "missing exact geometry " + rel;
          return nullptr;
        }
      }
    }
  } catch (const std::exception& ex) {
    error = ex.what();
    return nullptr;
  }
  if (const fbv::Json* brep = fbv::field(package->manifest, "brep")) {
    if (const fbv::Json* codec = fbv::field(*brep, "codec"))
      package->brep_codec = codec->as_string();
  }
  if (package->brep_codec == "analytic-box-v1") {
    if (!load_brep(*package, error)) return nullptr;
  }
  return package.release();
}
