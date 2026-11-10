#include "write_pkg.hpp"

#include "discipline.hpp"
#include "mesh_stream.hpp"
#include "scene.hpp"

#include "fbv/convert.hpp"
#include "fbv/io.hpp"
#include "fbv/json.hpp"
#include "fbv/sha256.hpp"
#include "fbv/sqlite_schema.hpp"
#include "fbv/sqlite_util.hpp"
#include "fbv/zip.hpp"
#include "fbv_version.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <ctime>
#include <fstream>
#include <map>
#include <sstream>
#include <tuple>

namespace fbv {
namespace {

std::filesystem::path make_temp_dir() {
  const auto base = std::filesystem::temp_directory_path();
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  for (int i = 0; i < 1000; ++i) {
    auto path = base / ("fbvconv-" + std::to_string(stamp) + "-" + std::to_string(i));
    if (std::filesystem::create_directory(path)) return path;
  }
  throw std::runtime_error("cannot create a temporary directory");
}

void append_u32(std::vector<std::uint8_t>& out, std::uint32_t value) {
  for (int i = 0; i < 4; ++i) out.push_back(static_cast<std::uint8_t>((value >> (8 * i)) & 0xff));
}

void append_u64(std::vector<std::uint8_t>& out, std::uint64_t value) {
  for (int i = 0; i < 8; ++i) out.push_back(static_cast<std::uint8_t>((value >> (8 * i)) & 0xff));
}

void append_f64(std::vector<std::uint8_t>& out, double value) {
  std::uint64_t bits = 0;
  static_assert(sizeof(double) == 8, "IEEE754 double required");
  std::memcpy(&bits, &value, sizeof(bits));
  append_u64(out, bits);
}

std::string utc_now() {
  const std::time_t now = std::time(nullptr);
  std::tm tm{};
#if defined(_WIN32)
  gmtime_s(&tm, &now);
#else
  gmtime_r(&now, &tm);
#endif
  char buf[64];
  std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
  return buf;
}

struct GlbRange {
  std::uint32_t pos_offset = 0;
  std::uint32_t pos_count = 0;
  std::uint32_t normal_offset = 0;
  std::uint32_t index_offset = 0;
  std::uint32_t index_count = 0;
  float min_v[3]{};
  float max_v[3]{};
  const Element* element = nullptr;
};

void write_as_floats(std::ostream& out, const std::vector<double>& values) {
  std::vector<float> chunk;
  chunk.reserve(4096);
  for (std::size_t i = 0; i < values.size();) {
    chunk.clear();
    const std::size_t n = std::min<std::size_t>(4096, values.size() - i);
    for (std::size_t k = 0; k < n; ++k) chunk.push_back(static_cast<float>(values[i + k]));
    out.write(reinterpret_cast<const char*>(chunk.data()),
              static_cast<std::streamsize>(chunk.size() * sizeof(float)));
    i += n;
  }
}

void append_file(std::ostream& out, const std::filesystem::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("cannot read " + path.string());
  out << in.rdbuf();
}

// BIN payload is written to scratch files and copied into the GLB so the triangle
// buffer is not held twice. A mesh that was spilled during conversion is loaded
// for one element at a time and released again before the next element.
void write_glb_file(Scene& scene, const std::filesystem::path& path,
                    const std::vector<Element*>& elements, bool release) {
  std::vector<Element*> live;
  for (Element* element : elements) {
    if (element == nullptr || !element->has_mesh) continue;
    if (element->mesh.indices.empty() && element->mesh_scratch.empty() &&
        element->triangle_count <= 0)
      continue;
    live.push_back(element);
  }
  const auto scratch_dir =
      path.parent_path().empty() ? std::filesystem::path(".") : path.parent_path();
  const auto pos_path = scratch_dir / (path.filename().string() + ".pos");
  const auto nrm_path = scratch_dir / (path.filename().string() + ".nrm");
  const auto idx_path = scratch_dir / (path.filename().string() + ".idx");
  struct Scratch {
    std::filesystem::path pos, nrm, idx;
    ~Scratch() {
      std::error_code ec;
      std::filesystem::remove(pos, ec);
      std::filesystem::remove(nrm, ec);
      std::filesystem::remove(idx, ec);
    }
  } scratch{pos_path, nrm_path, idx_path};

  std::ofstream pos_out(pos_path, std::ios::binary | std::ios::trunc);
  std::ofstream nrm_out(nrm_path, std::ios::binary | std::ios::trunc);
  std::ofstream idx_out(idx_path, std::ios::binary | std::ios::trunc);
  if (!pos_out || !nrm_out || !idx_out)
    throw std::runtime_error("cannot create mesh scratch files");

  std::vector<GlbRange> ranges;
  std::uint32_t vertex_cursor = 0;
  std::uint32_t normal_cursor = 0;
  std::uint32_t index_cursor = 0;
  for (Element* element : live) {
    prepare_mesh_for_write(scene, *element);
    if (element->mesh.indices.empty()) continue;
    GlbRange range;
    range.element = element;
    range.pos_offset = vertex_cursor;
    range.pos_count = static_cast<std::uint32_t>(element->mesh.position.size() / 3);
    range.normal_offset = normal_cursor;
    range.index_offset = index_cursor;
    range.index_count = static_cast<std::uint32_t>(element->mesh.indices.size());
    bool init = false;
    for (std::size_t i = 0; i + 2 < element->mesh.position.size(); i += 3) {
      const float x = static_cast<float>(element->mesh.position[i]);
      const float y = static_cast<float>(element->mesh.position[i + 1]);
      const float z = static_cast<float>(element->mesh.position[i + 2]);
      if (!init) {
        range.min_v[0] = range.max_v[0] = x;
        range.min_v[1] = range.max_v[1] = y;
        range.min_v[2] = range.max_v[2] = z;
        init = true;
      } else {
        range.min_v[0] = std::min(range.min_v[0], x);
        range.min_v[1] = std::min(range.min_v[1], y);
        range.min_v[2] = std::min(range.min_v[2], z);
        range.max_v[0] = std::max(range.max_v[0], x);
        range.max_v[1] = std::max(range.max_v[1], y);
        range.max_v[2] = std::max(range.max_v[2], z);
      }
    }
    write_as_floats(pos_out, element->mesh.position);
    write_as_floats(nrm_out, element->mesh.normal);
    if (!element->mesh.indices.empty()) {
      idx_out.write(
          reinterpret_cast<const char*>(element->mesh.indices.data()),
          static_cast<std::streamsize>(element->mesh.indices.size() * sizeof(std::uint32_t)));
    }
    vertex_cursor += range.pos_count;
    normal_cursor += static_cast<std::uint32_t>(element->mesh.normal.size() / 3);
    index_cursor += range.index_count;
    ranges.push_back(range);
    if (release || !element->mesh_scratch.empty()) release_mesh_ram(*element);
  }
  pos_out.close();
  nrm_out.close();
  idx_out.close();

  const auto pos_bytes = static_cast<std::uint32_t>(std::filesystem::file_size(pos_path));
  const auto nrm_bytes = static_cast<std::uint32_t>(std::filesystem::file_size(nrm_path));
  const auto idx_bytes = static_cast<std::uint32_t>(std::filesystem::file_size(idx_path));
  const auto bin_bytes = pos_bytes + nrm_bytes + idx_bytes;

  Json root = Json::object();
  Json asset = Json::object();
  asset.set("version", Json::string("2.0"));
  asset.set("generator", Json::string(std::string("fbvconv ") + FBV_VERSION_STRING));
  root.set("asset", std::move(asset));
  root.set("scene", Json::integer(0));
  Json scenes = Json::array();
  Json gltf_scene = Json::object();
  Json scene_nodes = Json::array();
  scene_nodes.push(Json::integer(0));
  gltf_scene.set("nodes", std::move(scene_nodes));
  scenes.push(std::move(gltf_scene));
  root.set("scenes", std::move(scenes));

  Json nodes = Json::array();
  Json root_node = Json::object();
  root_node.set("name", Json::string("root"));
  Json children = Json::array();
  for (std::size_t i = 0; i < ranges.size(); ++i)
    children.push(Json::integer(static_cast<std::int64_t>(i + 1)));
  if (!ranges.empty()) root_node.set("children", std::move(children));
  nodes.push(std::move(root_node));

  Json meshes = Json::array();
  Json materials = Json::array();
  Json accessors = Json::array();
  Json views = Json::array();
  auto add_view = [&](std::uint32_t offset, std::uint32_t length, int target) {
    Json view = Json::object();
    view.set("buffer", Json::integer(0));
    view.set("byteOffset", Json::integer(offset));
    view.set("byteLength", Json::integer(length));
    view.set("target", Json::integer(target));
    views.push(std::move(view));
    return static_cast<std::int64_t>(views.arr.size() - 1);
  };
  const std::uint32_t normal_bin = pos_bytes;
  const std::uint32_t index_bin = pos_bytes + nrm_bytes;
  for (std::size_t i = 0; i < ranges.size(); ++i) {
    const GlbRange& range = ranges[i];
    const auto pos_view = add_view(range.pos_offset * static_cast<std::uint32_t>(sizeof(float) * 3),
                                   range.pos_count * 12, 34962);
    const auto nrm_view =
        add_view(normal_bin + range.normal_offset * 12, range.pos_count * 12, 34962);
    const auto idx_view =
        add_view(index_bin + range.index_offset * static_cast<std::uint32_t>(sizeof(std::uint32_t)),
                 range.index_count * 4, 34963);
    const auto acc_pos = static_cast<std::int64_t>(accessors.arr.size());
    Json apos = Json::object();
    apos.set("bufferView", Json::integer(pos_view));
    apos.set("componentType", Json::integer(5126));
    apos.set("count", Json::integer(range.pos_count));
    apos.set("type", Json::string("VEC3"));
    Json amin = Json::array();
    Json amax = Json::array();
    for (int axis = 0; axis < 3; ++axis) {
      amin.push(Json::real(range.min_v[axis]));
      amax.push(Json::real(range.max_v[axis]));
    }
    apos.set("min", std::move(amin));
    apos.set("max", std::move(amax));
    accessors.push(std::move(apos));
    const auto acc_nrm = static_cast<std::int64_t>(accessors.arr.size());
    Json anrm = Json::object();
    anrm.set("bufferView", Json::integer(nrm_view));
    anrm.set("componentType", Json::integer(5126));
    anrm.set("count", Json::integer(range.pos_count));
    anrm.set("type", Json::string("VEC3"));
    accessors.push(std::move(anrm));
    const auto acc_idx = static_cast<std::int64_t>(accessors.arr.size());
    Json aidx = Json::object();
    aidx.set("bufferView", Json::integer(idx_view));
    aidx.set("componentType", Json::integer(5125));
    aidx.set("count", Json::integer(range.index_count));
    aidx.set("type", Json::string("SCALAR"));
    accessors.push(std::move(aidx));

    Json material = Json::object();
    material.set("name", Json::string(range.element->ifc_class));
    material.set("doubleSided", Json::boolean(true));
    Json pbr = Json::object();
    Json color = Json::array();
    color.push(Json::real(range.element->color[0]));
    color.push(Json::real(range.element->color[1]));
    color.push(Json::real(range.element->color[2]));
    color.push(Json::real(1));
    pbr.set("baseColorFactor", std::move(color));
    pbr.set("metallicFactor", Json::real(0));
    pbr.set("roughnessFactor", Json::real(0.85));
    material.set("pbrMetallicRoughness", std::move(pbr));
    const auto material_index = static_cast<std::int64_t>(materials.arr.size());
    materials.push(std::move(material));

    Json primitive = Json::object();
    Json attributes = Json::object();
    attributes.set("POSITION", Json::integer(acc_pos));
    attributes.set("NORMAL", Json::integer(acc_nrm));
    primitive.set("attributes", std::move(attributes));
    primitive.set("indices", Json::integer(acc_idx));
    primitive.set("material", Json::integer(material_index));
    primitive.set("mode", Json::integer(4));
    Json prims = Json::array();
    prims.push(std::move(primitive));
    Json mesh = Json::object();
    mesh.set("primitives", std::move(prims));
    meshes.push(std::move(mesh));

    Json node = Json::object();
    node.set("name", Json::string(std::to_string(range.element->id)));
    node.set("mesh", Json::integer(static_cast<std::int64_t>(i)));
    Json extras = Json::object();
    extras.set("elementId", Json::integer(range.element->id));
    node.set("extras", std::move(extras));
    nodes.push(std::move(node));
  }
  root.set("nodes", std::move(nodes));
  if (!ranges.empty()) {
    root.set("meshes", std::move(meshes));
    root.set("materials", std::move(materials));
    root.set("accessors", std::move(accessors));
    root.set("bufferViews", std::move(views));
    Json buffers = Json::array();
    Json buffer = Json::object();
    buffer.set("byteLength", Json::integer(bin_bytes));
    buffers.push(std::move(buffer));
    root.set("buffers", std::move(buffers));
  }

  std::string json = root.dump(0);
  while (json.size() % 4 != 0) json.push_back(' ');
  const std::uint32_t bin_padded = (bin_bytes + 3u) & ~3u;
  const std::uint32_t total = 12u + 8u + static_cast<std::uint32_t>(json.size()) + 8u + bin_padded;
  std::ofstream glb(path, std::ios::binary | std::ios::trunc);
  if (!glb) throw std::runtime_error("cannot write " + path.string());
  auto write_u32 = [&](std::uint32_t value) {
    char bytes[4];
    for (int i = 0; i < 4; ++i) bytes[i] = static_cast<char>((value >> (8 * i)) & 0xff);
    glb.write(bytes, 4);
  };
  write_u32(0x46546C67u);
  write_u32(2u);
  write_u32(total);
  write_u32(static_cast<std::uint32_t>(json.size()));
  write_u32(0x4E4F534Au);
  glb.write(json.data(), static_cast<std::streamsize>(json.size()));
  write_u32(bin_padded);
  write_u32(0x004E4942u);
  if (bin_bytes != 0) {
    append_file(glb, pos_path);
    append_file(glb, nrm_path);
    append_file(glb, idx_path);
  }
  for (std::uint32_t i = bin_bytes; i < bin_padded; ++i) {
    const char zero = 0;
    glb.write(&zero, 1);
  }
}

void bind_optional_id(Stmt& stmt, int index, std::int64_t id) {
  if (id == 0)
    stmt.bind_null(index);
  else
    stmt.bind_int64(index, id);
}

const TypeInfo* find_type(const Scene& scene, std::int64_t ifc_id) {
  for (const TypeInfo& type : scene.types) {
    if (type.ifc_id == ifc_id) return &type;
  }
  return nullptr;
}

void write_sqlite(const Scene& scene, const std::filesystem::path& path) {
  SqliteDb db(path, true);
  db.exec("BEGIN");
  db.exec(kSqliteSchema);
  auto spatial =
      db.prepare("INSERT INTO spatial(id, kind, name, elevation, parent_id) VALUES (?,?,?,?,?)");
  for (const SpatialNode& node : scene.spatial) {
    spatial.bind_int64(1, node.id);
    spatial.bind_text(2, node.kind);
    spatial.bind_text(3, node.name);
    if (node.has_elevation)
      spatial.bind_double(4, node.elevation_m);
    else
      spatial.bind_null(4);
    bind_optional_id(spatial, 5, node.parent_id);
    spatial.step_done();
    sqlite3_reset(spatial.get());
    sqlite3_clear_bindings(spatial.get());
  }
  auto types = db.prepare(
      "INSERT INTO types(id, guid, ifc_class, name, predefined_type) VALUES (?,?,?,?,?)");
  for (const TypeInfo& type : scene.types) {
    types.bind_int64(1, type.row_id);
    types.bind_text(2, type.guid);
    types.bind_text(3, type.ifc_class);
    types.bind_text(4, type.name);
    types.bind_text(5, type.predefined);
    types.step_done();
    sqlite3_reset(types.get());
    sqlite3_clear_bindings(types.get());
  }

  std::map<std::string, std::int64_t> material_ids;
  auto insert_material = db.prepare("INSERT INTO materials(id, name, category) VALUES (?,?,?)");
  auto material_id_of = [&](const std::string& name) {
    const auto it = material_ids.find(name);
    if (it != material_ids.end()) return it->second;
    const auto id = static_cast<std::int64_t>(material_ids.size() + 1);
    insert_material.bind_int64(1, id);
    insert_material.bind_text(2, name);
    insert_material.bind_null(3);
    insert_material.step_done();
    sqlite3_reset(insert_material.get());
    sqlite3_clear_bindings(insert_material.get());
    material_ids.emplace(name, id);
    return id;
  };

  auto insert_set = db.prepare("INSERT INTO material_sets(id, name) VALUES (?,?)");
  auto insert_layer = db.prepare(
      "INSERT INTO material_layers(set_id, material_id, thickness, layer_order) VALUES (?,?,?,?)");
  auto insert_element = db.prepare(
      "INSERT INTO elements(id, guid, ifc_class, name, tag, type_id, storey_id, parent_id, "
      "material_set_id, "
      "bbox_min_x, bbox_min_y, bbox_min_z, bbox_max_x, bbox_max_y, bbox_max_z, mesh_node, "
      "brep_ref, "
      "color_r, color_g, color_b) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
  auto insert_pset =
      db.prepare("INSERT INTO psets(id, element_id, type_id, name, source) VALUES (?,?,?,?,?)");
  auto insert_prop = db.prepare(
      "INSERT INTO props(pset_id, name, value_text, value_num, unit, data_type) VALUES "
      "(?,?,?,?,?,?)");
  auto insert_qty = db.prepare(
      "INSERT INTO quantities(element_id, qset, name, value, unit, kind) VALUES (?,?,?,?,?,?)");
  auto insert_class =
      db.prepare("INSERT INTO classification(element_id, system, code, title) VALUES (?,?,?,?)");
  auto insert_fts = db.prepare(
      "INSERT INTO fts_elements(element_id, name, tag, guid, type_name, prop_values) VALUES "
      "(?,?,?,?,?,?)");

  std::int64_t pset_id = 1;
  std::int64_t set_id = 1;
  const auto write_pset = [&](const Pset& pset, std::int64_t element_id, std::int64_t type_id) {
    insert_pset.bind_int64(1, pset_id);
    bind_optional_id(insert_pset, 2, element_id);
    bind_optional_id(insert_pset, 3, type_id);
    insert_pset.bind_text(4, pset.name);
    insert_pset.bind_text(5, pset.source);
    insert_pset.step_done();
    sqlite3_reset(insert_pset.get());
    sqlite3_clear_bindings(insert_pset.get());
    for (const PropValue& prop : pset.props) {
      insert_prop.bind_int64(1, pset_id);
      insert_prop.bind_text(2, prop.name);
      insert_prop.bind_text(3, prop.value_text);
      if (prop.has_num)
        insert_prop.bind_double(4, prop.value_num);
      else
        insert_prop.bind_null(4);
      if (prop.unit.empty())
        insert_prop.bind_null(5);
      else
        insert_prop.bind_text(5, prop.unit);
      insert_prop.bind_text(6, prop.data_type);
      insert_prop.step_done();
      sqlite3_reset(insert_prop.get());
      sqlite3_clear_bindings(insert_prop.get());
    }
    ++pset_id;
  };

  for (const TypeInfo& type : scene.types) {
    for (const Pset& pset : type.psets) write_pset(pset, 0, type.row_id);
  }

  for (const Element& element : scene.elements) {
    std::int64_t material_set = 0;
    if (!element.layers.empty()) {
      material_set = set_id++;
      insert_set.bind_int64(1, material_set);
      insert_set.bind_text(2, element.material_set_name);
      insert_set.step_done();
      sqlite3_reset(insert_set.get());
      sqlite3_clear_bindings(insert_set.get());
      int order = 0;
      for (const LayerValue& layer : element.layers) {
        insert_layer.bind_int64(1, material_set);
        insert_layer.bind_int64(2, material_id_of(layer.material));
        if (layer.has_thickness)
          insert_layer.bind_double(3, layer.thickness_m);
        else
          insert_layer.bind_null(3);
        insert_layer.bind_int64(4, order++);
        insert_layer.step_done();
        sqlite3_reset(insert_layer.get());
        sqlite3_clear_bindings(insert_layer.get());
      }
    }
    const TypeInfo* type = find_type(scene, element.type_ifc);
    insert_element.bind_int64(1, element.id);
    insert_element.bind_text(2, element.guid);
    insert_element.bind_text(3, element.ifc_class);
    insert_element.bind_text(4, element.name);
    insert_element.bind_text(5, element.tag);
    bind_optional_id(insert_element, 6, type != nullptr ? type->row_id : 0);
    bind_optional_id(insert_element, 7, element.storey_id);
    bind_optional_id(insert_element, 8, element.parent_id);
    bind_optional_id(insert_element, 9, material_set);
    if (element.has_bbox) {
      insert_element.bind_double(10, element.bbox_min[0]);
      insert_element.bind_double(11, element.bbox_min[1]);
      insert_element.bind_double(12, element.bbox_min[2]);
      insert_element.bind_double(13, element.bbox_max[0]);
      insert_element.bind_double(14, element.bbox_max[1]);
      insert_element.bind_double(15, element.bbox_max[2]);
    } else {
      for (int col = 10; col <= 15; ++col) insert_element.bind_null(col);
    }
    if (element.mesh_node >= 0)
      insert_element.bind_int64(16, element.mesh_node);
    else
      insert_element.bind_null(16);
    if (element.brep_ref >= 0)
      insert_element.bind_int64(17, element.brep_ref);
    else
      insert_element.bind_null(17);
    insert_element.bind_double(18, element.color[0]);
    insert_element.bind_double(19, element.color[1]);
    insert_element.bind_double(20, element.color[2]);
    insert_element.step_done();
    sqlite3_reset(insert_element.get());
    sqlite3_clear_bindings(insert_element.get());

    for (const Pset& pset : element.psets) write_pset(pset, element.id, 0);
    for (const QuantityValue& quantity : element.quantities) {
      insert_qty.bind_int64(1, element.id);
      insert_qty.bind_text(2, quantity.qset);
      insert_qty.bind_text(3, quantity.name);
      insert_qty.bind_double(4, quantity.value);
      insert_qty.bind_text(5, quantity.unit);
      insert_qty.bind_text(6, quantity.kind);
      insert_qty.step_done();
      sqlite3_reset(insert_qty.get());
      sqlite3_clear_bindings(insert_qty.get());
    }
    for (const ClassifValue& item : element.classes) {
      insert_class.bind_int64(1, element.id);
      insert_class.bind_text(2, item.system);
      insert_class.bind_text(3, item.code);
      insert_class.bind_text(4, item.title);
      insert_class.step_done();
      sqlite3_reset(insert_class.get());
      sqlite3_clear_bindings(insert_class.get());
    }

    std::ostringstream blob;
    for (const Pset& pset : element.psets) {
      for (const PropValue& prop : pset.props) blob << prop.name << ' ' << prop.value_text << ' ';
    }
    if (type != nullptr) {
      for (const Pset& pset : type->psets) {
        for (const PropValue& prop : pset.props) blob << prop.name << ' ' << prop.value_text << ' ';
      }
    }
    for (const QuantityValue& quantity : element.quantities) {
      blob << quantity.name << ' ' << quantity.value << ' ';
    }
    for (const LayerValue& layer : element.layers) blob << layer.material << ' ';
    for (const ClassifValue& item : element.classes) {
      blob << item.system << ' ' << item.code << ' ' << item.title << ' ';
    }
    insert_fts.bind_int64(1, element.id);
    insert_fts.bind_text(2, element.name);
    insert_fts.bind_text(3, element.tag);
    insert_fts.bind_text(4, element.guid);
    insert_fts.bind_text(5, type != nullptr ? type->name : std::string());
    insert_fts.bind_text(6, blob.str());
    insert_fts.step_done();
    sqlite3_reset(insert_fts.get());
    sqlite3_clear_bindings(insert_fts.get());
  }

  auto insert_system =
      db.prepare("INSERT INTO systems(id, guid, ifc_class, name, description) VALUES (?,?,?,?,?)");
  auto insert_member =
      db.prepare("INSERT INTO system_elements(system_id, element_id) VALUES (?,?)");
  for (const SystemInfo& system : scene.systems) {
    insert_system.bind_int64(1, system.id);
    insert_system.bind_text(2, system.guid);
    insert_system.bind_text(3, system.ifc_class);
    insert_system.bind_text(4, system.name);
    insert_system.bind_text(5, system.description);
    insert_system.step_done();
    sqlite3_reset(insert_system.get());
    sqlite3_clear_bindings(insert_system.get());
    for (std::int64_t element_id : system.element_ids) {
      insert_member.bind_int64(1, system.id);
      insert_member.bind_int64(2, element_id);
      insert_member.step_done();
      sqlite3_reset(insert_member.get());
      sqlite3_clear_bindings(insert_member.get());
    }
  }

  std::map<std::int64_t, std::vector<std::pair<std::int64_t, std::string>>> systems_of;
  for (const SystemInfo& system : scene.systems) {
    const std::string text = system.name + " " + system.description;
    for (std::int64_t element_id : system.element_ids) {
      systems_of[element_id].push_back({system.id, text});
    }
  }
  struct TileKey {
    std::int64_t storey = 0;
    std::string discipline;
    bool operator<(const TileKey& other) const {
      return std::tie(storey, discipline) < std::tie(other.storey, other.discipline);
    }
  };
  std::map<TileKey, std::vector<std::int64_t>> tile_members;
  for (const Element& element : scene.elements) {
    std::vector<std::pair<std::int64_t, std::string>> membership = systems_of[element.id];
    std::sort(membership.begin(), membership.end(),
              [](const auto& a, const auto& b) { return a.first < b.first; });
    std::vector<std::string> texts;
    texts.reserve(membership.size());
    for (const auto& item : membership) texts.push_back(item.second);
    TileKey key;
    key.storey = element.storey_id;
    key.discipline = assign_discipline(element.ifc_class, texts);
    tile_members[key].push_back(element.id);
  }
  auto insert_tile =
      db.prepare("INSERT INTO tiles(id, storey_id, discipline, element_count) VALUES (?,?,?,?)");
  auto insert_tile_element =
      db.prepare("INSERT INTO tile_elements(tile_id, element_id) VALUES (?,?)");
  std::int64_t tile_id = 1;
  for (const auto& entry : tile_members) {
    insert_tile.bind_int64(1, tile_id);
    bind_optional_id(insert_tile, 2, entry.first.storey);
    insert_tile.bind_text(3, entry.first.discipline);
    insert_tile.bind_int64(4, static_cast<std::int64_t>(entry.second.size()));
    insert_tile.step_done();
    sqlite3_reset(insert_tile.get());
    sqlite3_clear_bindings(insert_tile.get());
    for (std::int64_t element_id : entry.second) {
      insert_tile_element.bind_int64(1, tile_id);
      insert_tile_element.bind_int64(2, element_id);
      insert_tile_element.step_done();
      sqlite3_reset(insert_tile_element.get());
      sqlite3_clear_bindings(insert_tile_element.get());
    }
    ++tile_id;
  }

  struct CountKey {
    std::int64_t storey = 0;
    std::string ifc_class;
    std::string type_name;
    std::string material;
    bool operator<(const CountKey& other) const {
      return std::tie(storey, ifc_class, type_name, material) <
             std::tie(other.storey, other.ifc_class, other.type_name, other.material);
    }
  };
  std::map<CountKey, int> counts;
  struct QtyKey {
    CountKey base;
    std::string kind;
    bool operator<(const QtyKey& other) const {
      if (base < other.base) return true;
      if (other.base < base) return false;
      return kind < other.kind;
    }
  };
  std::map<QtyKey, double> qty_sum;
  std::map<QtyKey, int> qty_n;
  for (const Element& element : scene.elements) {
    CountKey key;
    key.storey = element.storey_id;
    key.ifc_class = element.ifc_class;
    if (const TypeInfo* type = find_type(scene, element.type_ifc)) key.type_name = type->name;
    if (!element.layers.empty()) key.material = element.layers.front().material;
    counts[key] += 1;
    for (const QuantityValue& quantity : element.quantities) {
      QtyKey qkey;
      qkey.base = key;
      qkey.kind = quantity.kind;
      qty_sum[qkey] += quantity.value;
      qty_n[qkey] += 1;
    }
  }
  auto insert_spec = db.prepare(
      "INSERT INTO spec_views(storey_id, ifc_class, type_name, material_name, element_count, "
      "quantity_kind, "
      "quantity_sum) VALUES (?,?,?,?,?,?,?)");
  for (const auto& entry : counts) {
    bind_optional_id(insert_spec, 1, entry.first.storey);
    insert_spec.bind_text(2, entry.first.ifc_class);
    insert_spec.bind_text(3, entry.first.type_name);
    insert_spec.bind_text(4, entry.first.material);
    insert_spec.bind_int64(5, entry.second);
    insert_spec.bind_null(6);
    insert_spec.bind_null(7);
    insert_spec.step_done();
    sqlite3_reset(insert_spec.get());
    sqlite3_clear_bindings(insert_spec.get());
  }
  for (const auto& entry : qty_sum) {
    bind_optional_id(insert_spec, 1, entry.first.base.storey);
    insert_spec.bind_text(2, entry.first.base.ifc_class);
    insert_spec.bind_text(3, entry.first.base.type_name);
    insert_spec.bind_text(4, entry.first.base.material);
    insert_spec.bind_int64(5, qty_n[entry.first]);
    insert_spec.bind_text(6, entry.first.kind);
    insert_spec.bind_double(7, entry.second);
    insert_spec.step_done();
    sqlite3_reset(insert_spec.get());
    sqlite3_clear_bindings(insert_spec.get());
  }
  db.exec("COMMIT");
}

void write_brep(const Scene& scene, const std::filesystem::path& pack_path,
                const std::filesystem::path& index_path) {
  std::vector<const Element*> elements;
  for (const Element& element : scene.elements) {
    if (element.brep_ref >= 0 && element.has_bbox) elements.push_back(&element);
  }
  std::sort(elements.begin(), elements.end(),
            [](const Element* a, const Element* b) { return a->brep_ref < b->brep_ref; });
  std::vector<std::uint8_t> pack;
  pack.insert(pack.end(), {'F', 'B', 'V', 'B'});
  append_u32(pack, 1);
  append_u32(pack, static_cast<std::uint32_t>(elements.size()));
  std::vector<std::uint8_t> index;
  index.insert(index.end(), {'F', 'B', 'V', 'I'});
  append_u32(index, 1);
  append_u32(index, static_cast<std::uint32_t>(elements.size()));
  for (const Element* element : elements) {
    const auto offset = static_cast<std::uint64_t>(pack.size());
    append_u32(pack, 1);
    for (int axis = 0; axis < 3; ++axis) append_f64(pack, element->bbox_min[axis]);
    for (int axis = 0; axis < 3; ++axis) append_f64(pack, element->bbox_max[axis]);
    const auto length = static_cast<std::uint64_t>(pack.size() - offset);
    append_u64(index, static_cast<std::uint64_t>(element->id));
    append_u64(index, offset);
    append_u64(index, length);
    append_u32(index, 1);
    for (int i = 0; i < 12; ++i) {
      const double identity = (i == 0 || i == 5 || i == 10) ? 1.0 : 0.0;
      append_f64(index, identity);
    }
  }
  write_binary(pack_path, pack);
  write_binary(index_path, index);
}

Json part_record(const std::filesystem::path& path) {
  Json record = Json::object();
  record.set("sha256", Json::string(sha256_file(path)));
  record.set("bytes", Json::integer(static_cast<std::int64_t>(std::filesystem::file_size(path))));
  return record;
}

void copy_tree(const std::filesystem::path& from, const std::filesystem::path& to) {
  std::filesystem::remove_all(to);
  std::filesystem::create_directories(to);
  for (const auto& entry : std::filesystem::recursive_directory_iterator(from)) {
    const auto relative = std::filesystem::relative(entry.path(), from);
    const auto dest = to / relative;
    if (entry.is_directory())
      std::filesystem::create_directories(dest);
    else if (entry.is_regular_file()) {
      std::filesystem::create_directories(dest.parent_path());
      std::filesystem::copy_file(entry.path(), dest,
                                 std::filesystem::copy_options::overwrite_existing);
    }
  }
}

}  // namespace

void write_scene_package(Scene& scene, const ConvertOptions& options,
                         const std::string& source_bytes, const std::string& source_name) {
  if (options.output.empty()) throw std::runtime_error("output path is empty");
  int node = 1;
  int brep = 0;
  int triangles = 0;
  int with_mesh = 0;
  for (Element& element : scene.elements) {
    if (!element.has_mesh) continue;
    element.mesh_node = node++;
    if (options.write_brep && element.has_bbox) element.brep_ref = brep++;
    const int tri = element.triangle_count > 0 ? element.triangle_count
                                               : static_cast<int>(element.mesh.indices.size() / 3);
    triangles += tri;
    ++with_mesh;
  }
  scene.triangles = triangles;

  const auto staging = make_temp_dir();
  try {
    std::filesystem::create_directories(staging / "mesh" / "elements");
    std::vector<Element*> meshed;
    for (Element& element : scene.elements) {
      if (!element.has_mesh) continue;
      meshed.push_back(&element);
      write_glb_file(scene, staging / "mesh" / "elements" / (std::to_string(element.id) + ".glb"),
                     {&element}, false);
    }
    write_glb_file(scene, staging / "mesh" / "lod0.glb", meshed, true);
    clear_mesh_scratch(scene);
    write_sqlite(scene, staging / "meta.sqlite");
    if (options.write_brep) write_brep(scene, staging / "brep.pack", staging / "brep.index");

    Json manifest = Json::object();
    manifest.set("format_version", Json::integer(FBV_FORMAT_VERSION));
    manifest.set("generator", Json::string(std::string("fbvconv ") + FBV_VERSION_STRING));
    manifest.set("created_utc", Json::string(utc_now()));
    manifest.set("name", Json::string(scene.project_name));
    Json source = Json::object();
    source.set("filename", Json::string(source_name));
    source.set("schema", Json::string(scene.schema));
    source.set("sha256", Json::string(sha256_hex(sha256_bytes(source_bytes))));
    manifest.set("source", std::move(source));
    Json units = Json::object();
    units.set("length", Json::string("metre"));
    units.set("source_length_unit", Json::string(scene.length_unit_name));
    units.set("area", Json::string("square_metre"));
    units.set("volume", Json::string("cubic_metre"));
    units.set("ui_length", Json::string("millimetre"));
    manifest.set("units", std::move(units));
    Json origin = Json::array();
    origin.push(Json::real(scene.origin.x));
    origin.push(Json::real(scene.origin.y));
    origin.push(Json::real(scene.origin.z));
    manifest.set("local_origin", std::move(origin));
    Json bbox = Json::object();
    Json bmin = Json::array();
    Json bmax = Json::array();
    for (int axis = 0; axis < 3; ++axis) {
      bmin.push(Json::real(scene.has_world ? scene.world_min[axis] : 0));
      bmax.push(Json::real(scene.has_world ? scene.world_max[axis] : 0));
    }
    bbox.set("min", std::move(bmin));
    bbox.set("max", std::move(bmax));
    manifest.set("world_bbox", std::move(bbox));
    Json counts = Json::object();
    counts.set("spatial", Json::integer(static_cast<std::int64_t>(scene.spatial.size())));
    counts.set("elements", Json::integer(static_cast<std::int64_t>(scene.elements.size())));
    counts.set("elements_with_mesh", Json::integer(with_mesh));
    counts.set("elements_without_geometry",
               Json::integer(static_cast<std::int64_t>(scene.elements.size()) - with_mesh));
    counts.set("elements_failed", Json::integer(scene.failed));
    counts.set("triangles_lod0", Json::integer(triangles));
    counts.set("warnings", Json::integer(static_cast<std::int64_t>(scene.warnings.size())));
    manifest.set("counts", std::move(counts));
    manifest.set("completeness", Json::string(scene.completeness_ok ? "ok" : "incomplete"));
    Json mesh = Json::object();
    mesh.set("generator", Json::string(scene.mesh_generator));
    mesh.set("linear_deflection_m", Json::real(options.linear_deflection_m));
    mesh.set("angular_deflection_rad", Json::real(options.angular_deflection_rad));
    Json lods = Json::array();
    lods.push(Json::string("lod0"));
    mesh.set("lods", std::move(lods));
    mesh.set("instancing", Json::boolean(false));
    mesh.set("coordinate_space", Json::string("local_origin_metres_float32"));
    manifest.set("mesh", std::move(mesh));
    Json brep = Json::object();
    brep.set("codec", Json::string(options.write_brep ? "analytic-box-v1" : "none"));
    brep.set("coordinate_space", Json::string("world_metres_float64"));
    manifest.set("brep", std::move(brep));
    Json parts = Json::object();
    std::vector<std::filesystem::path> files;
    for (const auto& entry : std::filesystem::recursive_directory_iterator(staging)) {
      if (entry.is_regular_file()) files.push_back(entry.path());
    }
    std::sort(files.begin(), files.end());
    for (const auto& file : files) {
      parts.set(std::filesystem::relative(file, staging).generic_string(), part_record(file));
    }
    manifest.set("parts", std::move(parts));
    write_text(staging / "manifest.json", manifest.dump(2) + "\n");

    const std::filesystem::path output(options.output);
    if (options.as_directory) {
      copy_tree(staging, output);
    } else {
      if (output.has_parent_path()) std::filesystem::create_directories(output.parent_path());
      std::string zip_error;
      if (!zip_directory_stored(staging, output, zip_error)) throw std::runtime_error(zip_error);
    }
    std::filesystem::remove_all(staging);
  } catch (...) {
    std::filesystem::remove_all(staging);
    throw;
  }
}

}  // namespace fbv
