#pragma once

#include "fbv/convert.hpp"
#include "ifc_parse.hpp"
#include "math.hpp"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace fbv {

struct PropValue {
  std::string name;
  std::string value_text;
  bool has_num = false;
  double value_num = 0;
  std::string unit;
  std::string data_type;
};

struct Pset {
  std::string name;
  std::string source;
  std::vector<PropValue> props;
};

struct QuantityValue {
  std::string qset;
  std::string name;
  double value = 0;
  std::string unit;
  std::string kind;
};

struct LayerValue {
  std::string material;
  bool has_thickness = false;
  double thickness_m = 0;
};

struct ClassifValue {
  std::string system;
  std::string code;
  std::string title;
};

struct SpatialNode {
  std::int64_t ifc_id = 0;
  std::int64_t id = 0;
  std::int64_t parent_ifc = 0;
  std::int64_t parent_id = 0;
  std::string kind;
  std::string name;
  bool has_elevation = false;
  double elevation_m = 0;
};

struct TypeInfo {
  std::int64_t ifc_id = 0;
  std::int64_t row_id = 0;
  std::string guid;
  std::string ifc_class;
  std::string name;
  std::string predefined;
  std::vector<Pset> psets;
};

struct FailureNote {
  std::string guid;
  std::string ifc_class;
  std::string reason;
  std::string detail;
};

struct SystemInfo {
  std::int64_t ifc_id = 0;
  std::int64_t id = 0;
  std::string guid;
  std::string ifc_class;
  std::string name;
  std::string description;
  std::vector<std::int64_t> element_ids;
};

struct Element {
  std::int64_t ifc_id = 0;
  std::int64_t id = 0;
  std::string guid;
  std::string ifc_class;
  std::string name;
  std::string tag;
  std::int64_t type_ifc = 0;
  std::int64_t storey_id = 0;
  std::int64_t parent_id = 0;
  std::vector<Pset> psets;
  std::vector<QuantityValue> quantities;
  std::vector<LayerValue> layers;
  std::string material_set_name;
  std::vector<ClassifValue> classes;
  TriMesh mesh;
  bool has_mesh = false;
  bool has_representation = false;
  std::string mesh_source;
  std::string geometry_failure;
  std::string failure_reason;
  int triangle_count = 0;
  // World-space mesh spilled to disk so the element vector does not keep it.
  std::string mesh_scratch;
  bool mesh_local = false;
  std::uint64_t mesh_accounted_bytes = 0;
  bool has_bbox = false;
  double bbox_min[3]{};
  double bbox_max[3]{};
  float color[3]{0.7f, 0.72f, 0.74f};
  int mesh_node = -1;
  int brep_ref = -1;
};

struct Scene {
  std::string schema;
  std::string project_name;
  std::string length_unit_name = "metre";
  double length_scale = 1;
  double area_scale = 1;
  double volume_scale = 1;
  std::vector<SpatialNode> spatial;
  std::vector<TypeInfo> types;
  std::vector<Element> elements;
  std::vector<SystemInfo> systems;
  std::vector<std::string> warnings;
  std::map<std::string, int> warning_counts;
  std::vector<FailureNote> failures;
  std::vector<std::string> notes;
  std::vector<std::string> missing_guids;
  bool has_world = false;
  double world_min[3]{};
  double world_max[3]{};
  Vec3 origin;
  std::string mesh_generator = "analytic-extrusion-v1";
  std::string geometry_library = "analytic";
  std::string ifc_log;
  bool ifcopenshell_ran = false;
  bool ios_unavailable = false;
  bool completeness_ok = true;
  int failed = 0;
  int without_geometry = 0;
  int excluded = 0;
  int triangles = 0;
  int threads = 1;
  double geometry_seconds = 0;
  std::string mesh_scratch_dir;
  std::uint64_t mesh_resident_bytes = 0;
  std::uint64_t mesh_bytes_peak = 0;
};

void expand_bbox(Element& element, Vec3 point);
void add_warning(Scene& scene, const std::string& code, const std::string& text);
void remember_failure(Scene& scene, const Element& element, const std::string& code,
                      const std::string& detail);
std::string classify_geometry_failure(const std::string& text);

Scene build_scene(const IfcFile& file, const ConvertOptions& options, const std::string& ifc_text);

}  // namespace fbv
