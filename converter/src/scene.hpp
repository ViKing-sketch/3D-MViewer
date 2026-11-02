#pragma once

#include "ifc_parse.hpp"
#include "math.hpp"

#include <cstdint>
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
  std::vector<std::string> warnings;
  bool has_world = false;
  double world_min[3]{};
  double world_max[3]{};
  Vec3 origin;
};

Scene build_scene(const IfcFile& file, const std::vector<std::string>& class_filter);

}  // namespace fbv
