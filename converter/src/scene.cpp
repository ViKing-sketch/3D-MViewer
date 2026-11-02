#include "scene.hpp"

#include "ifc_geom_mesh.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <map>
#include <set>
#include <sstream>
#include <unordered_map>
#include <unordered_set>

namespace fbv {
namespace {

std::string upper_copy(std::string text) {
  for (char& c : text) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  return text;
}

const IfcValue* attr(const IfcEntity& entity, std::size_t index) {
  return index < entity.attrs.size() ? &entity.attrs[index] : nullptr;
}

std::int64_t ref_at(const IfcEntity& entity, std::size_t index) {
  const IfcValue* value = attr(entity, index);
  return value != nullptr && value->kind == IfcValue::Kind::Ref ? value->i : 0;
}

std::string str_at(const IfcEntity& entity, std::size_t index) {
  const IfcValue* value = attr(entity, index);
  return value != nullptr && value->kind == IfcValue::Kind::String ? value->text : std::string();
}

std::string enum_at(const IfcEntity& entity, std::size_t index) {
  const IfcValue* value = attr(entity, index);
  return value != nullptr && value->kind == IfcValue::Kind::Enum ? value->text : std::string();
}

bool num_at(const IfcEntity& entity, std::size_t index, double& out) {
  const IfcValue* value = attr(entity, index);
  if (value == nullptr) return false;
  if (value->kind == IfcValue::Kind::Real || value->kind == IfcValue::Kind::Integer) {
    out = value->real;
    return true;
  }
  return false;
}

std::vector<std::int64_t> refs_of(const IfcValue* value) {
  std::vector<std::int64_t> out;
  if (value == nullptr) return out;
  if (value->kind == IfcValue::Kind::Ref) out.push_back(value->i);
  if (value->kind == IfcValue::Kind::List) {
    for (const IfcValue& item : value->items) {
      if (item.kind == IfcValue::Kind::Ref) out.push_back(item.i);
    }
  }
  return out;
}

bool looks_like_product(const IfcEntity& entity) {
  const std::string& type = entity.type;
  if (type.size() < 6 || type.compare(0, 3, "IFC") != 0) return false;
  if (type.rfind("IFCREL", 0) == 0) return false;
  if (type.size() >= 4 && type.compare(type.size() - 4, 4, "TYPE") == 0) return false;
  static const std::unordered_set<std::string> kSpatial = {
      "IFCPROJECT",
      "IFCSITE",
      "IFCBUILDING",
      "IFCBUILDINGSTOREY",
      "IFCSPACE",
      "IFCEXTERNALSPATIALELEMENT",
      "IFCEXTERNALSPATIALSTRUCTUREELEMENT",
      "IFCSPATIALZONE",
      "IFCFACILITY",
      "IFCFACILITYPART",
      "IFCBRIDGE",
      "IFCROAD",
      "IFCRAILWAY",
      "IFCMARINEFACILITY",
  };
  if (kSpatial.count(type) != 0) return false;
  // IfcElement layout: GlobalId .. Tag is at least 8 attributes. IfcRoot property
  // sets and type objects are shorter or end in TYPE and stay out of the element table.
  if (type.find("REPRESENTATION") != std::string::npos ||
      type.find("CONTEXT") != std::string::npos || type.find("PROFILE") != std::string::npos)
    return false;
  if (entity.attrs.size() < 8) return false;
  // IfcElement.OwnerHistory is a reference. Geometry contexts store a string there.
  const IfcValue& history = entity.attrs[1];
  if (history.kind != IfcValue::Kind::Ref && history.kind != IfcValue::Kind::Null) return false;
  const IfcValue& guid = entity.attrs[0];
  return guid.kind == IfcValue::Kind::String && guid.text.size() == 22;
}

const char* canonical_class(const std::string& type) {
  if (type == "IFCWALL") return "IfcWall";
  if (type == "IFCWALLSTANDARDCASE") return "IfcWallStandardCase";
  if (type == "IFCSLAB") return "IfcSlab";
  if (type == "IFCSLABSTANDARDCASE") return "IfcSlabStandardCase";
  if (type == "IFCCOLUMN") return "IfcColumn";
  if (type == "IFCCOLUMNSTANDARDCASE") return "IfcColumnStandardCase";
  if (type == "IFCBEAM") return "IfcBeam";
  if (type == "IFCDOOR") return "IfcDoor";
  if (type == "IFCWINDOW") return "IfcWindow";
  if (type == "IFCPLATE") return "IfcPlate";
  if (type == "IFCMEMBER") return "IfcMember";
  if (type == "IFCROOF") return "IfcRoof";
  if (type == "IFCSTAIR") return "IfcStair";
  if (type == "IFCSTAIRFLIGHT") return "IfcStairFlight";
  if (type == "IFCRAILING") return "IfcRailing";
  if (type == "IFCCOVERING") return "IfcCovering";
  if (type == "IFCFOOTING") return "IfcFooting";
  if (type == "IFCPILE") return "IfcPile";
  if (type == "IFCFLOWSEGMENT") return "IfcFlowSegment";
  if (type == "IFCFLOWTERMINAL") return "IfcFlowTerminal";
  if (type == "IFCFLOWFITTING") return "IfcFlowFitting";
  if (type == "IFCFLOWCONTROLLER") return "IfcFlowController";
  if (type == "IFCBUILDINGELEMENTPROXY") return "IfcBuildingElementProxy";
  if (type == "IFCWALLTYPE") return "IfcWallType";
  if (type == "IFCSLABTYPE") return "IfcSlabType";
  if (type == "IFCCOLUMNTYPE") return "IfcColumnType";
  if (type == "IFCBEAMTYPE") return "IfcBeamType";
  return nullptr;
}

std::string class_name(const std::string& type) {
  if (const char* name = canonical_class(type)) return name;
  if (type.size() > 3 && type.compare(0, 3, "IFC") == 0) {
    std::string rest = type.substr(3);
    for (char& c : rest) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (!rest.empty())
      rest[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(rest[0])));
    return "Ifc" + rest;
  }
  return type;
}

void set_color(Element& element) {
  const std::string& cls = element.ifc_class;
  if (cls.find("Wall") != std::string::npos) {
    element.color[0] = 0.80f;
    element.color[1] = 0.78f;
    element.color[2] = 0.70f;
  } else if (cls.find("Slab") != std::string::npos || cls.find("Roof") != std::string::npos) {
    element.color[0] = 0.62f;
    element.color[1] = 0.62f;
    element.color[2] = 0.64f;
  } else if (cls.find("Column") != std::string::npos) {
    element.color[0] = 0.55f;
    element.color[1] = 0.58f;
    element.color[2] = 0.62f;
  } else if (cls.find("Beam") != std::string::npos || cls.find("Member") != std::string::npos) {
    element.color[0] = 0.45f;
    element.color[1] = 0.50f;
    element.color[2] = 0.58f;
  } else if (cls.find("Door") != std::string::npos) {
    element.color[0] = 0.55f;
    element.color[1] = 0.36f;
    element.color[2] = 0.22f;
  } else if (cls.find("Window") != std::string::npos || cls.find("Plate") != std::string::npos) {
    element.color[0] = 0.62f;
    element.color[1] = 0.80f;
    element.color[2] = 0.86f;
  }
}

bool class_allowed(const std::vector<std::string>& filter, const std::string& ifc_class) {
  if (filter.empty()) return true;
  const std::string cur = upper_copy(ifc_class);
  for (const std::string& item : filter) {
    if (upper_copy(item) == cur) return true;
  }
  return false;
}

double prefix_scale(const std::string& prefix) {
  if (prefix.empty()) return 1;
  if (prefix == "EXA") return 1e18;
  if (prefix == "PETA") return 1e15;
  if (prefix == "TERA") return 1e12;
  if (prefix == "GIGA") return 1e9;
  if (prefix == "MEGA") return 1e6;
  if (prefix == "KILO") return 1e3;
  if (prefix == "HECTO") return 1e2;
  if (prefix == "DECA") return 1e1;
  if (prefix == "DECI") return 1e-1;
  if (prefix == "CENTI") return 1e-2;
  if (prefix == "MILLI") return 1e-3;
  if (prefix == "MICRO") return 1e-6;
  if (prefix == "NANO") return 1e-9;
  if (prefix == "PICO") return 1e-12;
  if (prefix == "FEMTO") return 1e-15;
  if (prefix == "ATTO") return 1e-18;
  return 1;
}

std::string length_unit_name(const std::string& prefix, const std::string& name) {
  if (name == "METRE" && prefix == "MILLI") return "millimetre";
  if (name == "METRE" && prefix == "CENTI") return "centimetre";
  if (name == "METRE" && prefix.empty()) return "metre";
  if (name == "METRE" && prefix == "KILO") return "kilometre";
  if (prefix.empty()) return name;
  return prefix + " " + name;
}

bool cartesian(const IfcFile& file, std::int64_t id, double scale, Vec3& out) {
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCCARTESIANPOINT" || entity->attrs.empty() ||
      entity->attrs[0].kind != IfcValue::Kind::List) {
    return false;
  }
  const auto comp = [&](std::size_t index) {
    if (index >= entity->attrs[0].items.size()) return 0.0;
    const IfcValue& value = entity->attrs[0].items[index];
    if (value.kind == IfcValue::Kind::Real || value.kind == IfcValue::Kind::Integer) {
      return value.real * scale;
    }
    return 0.0;
  };
  out = {comp(0), comp(1), entity->attrs[0].items.size() > 2 ? comp(2) : 0};
  return true;
}

bool direction(const IfcFile& file, std::int64_t id, Vec3& out) {
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCDIRECTION" || entity->attrs.empty() ||
      entity->attrs[0].kind != IfcValue::Kind::List) {
    return false;
  }
  const auto comp = [&](std::size_t index) {
    if (index >= entity->attrs[0].items.size()) return 0.0;
    const IfcValue& value = entity->attrs[0].items[index];
    if (value.kind == IfcValue::Kind::Real || value.kind == IfcValue::Kind::Integer)
      return value.real;
    return 0.0;
  };
  out = {comp(0), comp(1), entity->attrs[0].items.size() > 2 ? comp(2) : 0};
  return true;
}

Mat4 frame3(Vec3 origin, Vec3 z_raw, Vec3 x_raw, bool has_z, bool has_x) {
  Vec3 z = has_z ? normalize(z_raw) : Vec3{0, 0, 1};
  if (length(z) < 1e-15) z = {0, 0, 1};
  Vec3 x = has_x ? x_raw : Vec3{1, 0, 0};
  x = x - z * dot(x, z);
  if (dot(x, x) < 1e-20) {
    const Vec3 tmp = std::abs(z.x) < 0.9 ? Vec3{1, 0, 0} : Vec3{0, 1, 0};
    x = tmp - z * dot(tmp, z);
  }
  x = normalize(x);
  const Vec3 y = cross(z, x);
  return frame_from_axes(origin, x, y, z);
}

Mat4 axis3(const IfcFile& file, std::int64_t id, double scale) {
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCAXIS2PLACEMENT3D") return Mat4::identity();
  Vec3 origin;
  if (const std::int64_t loc = ref_at(*entity, 0)) cartesian(file, loc, scale, origin);
  Vec3 z{0, 0, 1};
  Vec3 x{1, 0, 0};
  const bool has_z = ref_at(*entity, 1) != 0 && direction(file, ref_at(*entity, 1), z);
  const bool has_x = ref_at(*entity, 2) != 0 && direction(file, ref_at(*entity, 2), x);
  return frame3(origin, z, x, has_z, has_x);
}

Frame2 axis2(const IfcFile& file, std::int64_t id, double scale) {
  Frame2 frame;
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCAXIS2PLACEMENT2D") return frame;
  Vec3 origin;
  if (const std::int64_t loc = ref_at(*entity, 0)) cartesian(file, loc, scale, origin);
  frame.origin = {origin.x, origin.y};
  Vec3 ref{1, 0, 0};
  if (const std::int64_t rid = ref_at(*entity, 1)) direction(file, rid, ref);
  const double n = std::sqrt(ref.x * ref.x + ref.y * ref.y);
  if (n > 1e-15) {
    frame.x = {ref.x / n, ref.y / n};
    frame.y = {-frame.x.y, frame.x.x};
  }
  return frame;
}

Mat4 placement(const IfcFile& file, std::int64_t id, double scale, int depth) {
  if (id == 0 || depth > 32) return Mat4::identity();
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCLOCALPLACEMENT") return Mat4::identity();
  const Mat4 parent = ref_at(*entity, 0) != 0
                          ? placement(file, ref_at(*entity, 0), scale, depth + 1)
                          : Mat4::identity();
  const Mat4 relative =
      ref_at(*entity, 1) != 0 ? axis3(file, ref_at(*entity, 1), scale) : Mat4::identity();
  return mul(parent, relative);
}

void ensure_ccw(std::vector<Vec2>& pts) {
  double area = 0;
  for (std::size_t i = 0; i < pts.size(); ++i) {
    const Vec2& a = pts[i];
    const Vec2& b = pts[(i + 1) % pts.size()];
    area += a.x * b.y - b.x * a.y;
  }
  if (area < 0) std::reverse(pts.begin(), pts.end());
}

bool profile_points(const IfcFile& file, std::int64_t id, double scale, std::vector<Vec2>& pts,
                    std::string& why) {
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr) {
    why = "missing profile";
    return false;
  }
  if (entity->type == "IFCRECTANGLEPROFILEDEF") {
    double xdim = 0;
    double ydim = 0;
    if (!num_at(*entity, 3, xdim) || !num_at(*entity, 4, ydim)) {
      why = "IfcRectangleProfileDef is missing dimensions";
      return false;
    }
    xdim *= scale;
    ydim *= scale;
    const double hx = xdim * 0.5;
    const double hy = ydim * 0.5;
    const Vec2 local[4] = {{-hx, -hy}, {hx, -hy}, {hx, hy}, {-hx, hy}};
    const Frame2 frame =
        ref_at(*entity, 2) != 0 ? axis2(file, ref_at(*entity, 2), scale) : Frame2{};
    for (Vec2 point : local) pts.push_back(frame.apply(point));
    ensure_ccw(pts);
    return true;
  }
  if (entity->type == "IFCCIRCLEPROFILEDEF") {
    double radius = 0;
    if (!num_at(*entity, 3, radius)) {
      why = "IfcCircleProfileDef is missing Radius";
      return false;
    }
    radius *= scale;
    const Frame2 frame =
        ref_at(*entity, 2) != 0 ? axis2(file, ref_at(*entity, 2), scale) : Frame2{};
    constexpr int kSegments = 24;
    for (int i = 0; i < kSegments; ++i) {
      const double angle = (2.0 * 3.14159265358979323846 * i) / kSegments;
      pts.push_back(frame.apply({radius * std::cos(angle), radius * std::sin(angle)}));
    }
    ensure_ccw(pts);
    return true;
  }
  if (entity->type == "IFCARBITRARYCLOSEDPROFILEDEF") {
    // IFC2X3 stores OuterCurve at index 1. IFC4 inserts ProfileName before it.
    const std::int64_t curve_id = ref_at(*entity, 2) != 0 ? ref_at(*entity, 2) : ref_at(*entity, 1);
    const IfcEntity* curve = file.find(curve_id);
    if (curve == nullptr || curve->type != "IFCPOLYLINE" || curve->attrs.empty() ||
        curve->attrs[0].kind != IfcValue::Kind::List) {
      why = "arbitrary profile curve is not an IfcPolyline";
      return false;
    }
    for (const IfcValue& item : curve->attrs[0].items) {
      if (item.kind != IfcValue::Kind::Ref) continue;
      Vec3 point;
      if (!cartesian(file, item.i, scale, point)) continue;
      pts.push_back({point.x, point.y});
    }
    if (pts.size() >= 2 && std::abs(pts.front().x - pts.back().x) < 1e-9 &&
        std::abs(pts.front().y - pts.back().y) < 1e-9) {
      pts.pop_back();
    }
    if (pts.size() < 3) {
      why = "polyline profile has fewer than 3 points";
      return false;
    }
    ensure_ccw(pts);
    return true;
  }
  why = "unsupported profile " + entity->type;
  return false;
}

bool extrude_solid(const IfcFile& file, const IfcEntity& solid, double scale, const Mat4& product,
                   TriMesh& mesh, std::string& why) {
  std::vector<Vec2> profile;
  if (!profile_points(file, ref_at(solid, 0), scale, profile, why)) return false;
  const Mat4 position =
      ref_at(solid, 1) != 0 ? axis3(file, ref_at(solid, 1), scale) : Mat4::identity();
  Vec3 dir{0, 0, 1};
  if (const std::int64_t did = ref_at(solid, 2)) direction(file, did, dir);
  dir = normalize(dir);
  if (length(dir) < 1e-15) {
    why = "extrusion direction is zero";
    return false;
  }
  double depth = 0;
  if (!num_at(solid, 3, depth) || depth == 0) {
    why = "extrusion depth is missing";
    return false;
  }
  depth *= scale;
  const Mat4 placed = mul(product, position);
  const Vec3 extrude = transform_vector(placed, dir * depth);
  std::vector<Vec3> bottom;
  bottom.reserve(profile.size());
  for (Vec2 point : profile) bottom.push_back(transform_point(placed, {point.x, point.y, 0}));
  add_prism(mesh, bottom, extrude);
  return !mesh.indices.empty();
}

bool mesh_item(const IfcFile& file, const IfcEntity& item, double scale, const Mat4& product,
               TriMesh& mesh, std::string& why) {
  if (item.type == "IFCEXTRUDEDAREASOLID")
    return extrude_solid(file, item, scale, product, mesh, why);
  if (item.type == "IFCMAPPEDITEM") {
    why = "IfcMappedItem instancing is not expanded by the analytic mesher";
    return false;
  }
  if (item.type == "IFCBOOLEANCLIPPINGRESULT" || item.type == "IFCBOOLEANRESULT") {
    why = "boolean clippings and openings are not evaluated by the analytic mesher";
    return false;
  }
  why = "unsupported geometry " + item.type;
  return false;
}

bool mesh_product(const IfcFile& file, const IfcEntity& product, double scale, TriMesh& mesh,
                  std::string& why) {
  const IfcEntity* shape = file.find(ref_at(product, 6));
  if (shape == nullptr) {
    why = "no representation";
    return false;
  }
  const std::vector<std::int64_t> reps = refs_of(attr(*shape, 2));
  if (reps.empty()) {
    why = "representation has no items";
    return false;
  }
  std::vector<std::int64_t> ordered = reps;
  std::stable_sort(ordered.begin(), ordered.end(), [&](std::int64_t a, std::int64_t b) {
    const auto score = [&](std::int64_t id) {
      const IfcEntity* rep = file.find(id);
      if (rep == nullptr) return 0;
      if (str_at(*rep, 1) == "Body" || str_at(*rep, 2) == "SweptSolid") return 2;
      return 1;
    };
    return score(a) > score(b);
  });
  const Mat4 world = placement(file, ref_at(product, 5), scale, 0);
  bool any = false;
  for (std::int64_t rep_id : ordered) {
    const IfcEntity* rep = file.find(rep_id);
    if (rep == nullptr) continue;
    for (std::int64_t item_id : refs_of(attr(*rep, 3))) {
      const IfcEntity* item = file.find(item_id);
      if (item == nullptr) continue;
      std::string item_why;
      if (mesh_item(file, *item, scale, world, mesh, item_why))
        any = true;
      else
        why = item_why;
    }
    if (any) return true;
  }
  if (why.empty()) why = "no supported solid";
  return false;
}

void expand_bbox(Element& element, Vec3 point) {
  if (!element.has_bbox) {
    element.bbox_min[0] = element.bbox_max[0] = point.x;
    element.bbox_min[1] = element.bbox_max[1] = point.y;
    element.bbox_min[2] = element.bbox_max[2] = point.z;
    element.has_bbox = true;
    return;
  }
  element.bbox_min[0] = std::min(element.bbox_min[0], point.x);
  element.bbox_min[1] = std::min(element.bbox_min[1], point.y);
  element.bbox_min[2] = std::min(element.bbox_min[2], point.z);
  element.bbox_max[0] = std::max(element.bbox_max[0], point.x);
  element.bbox_max[1] = std::max(element.bbox_max[1], point.y);
  element.bbox_max[2] = std::max(element.bbox_max[2], point.z);
}

std::string format_num(double value) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.15g", value);
  return buf;
}

void read_nominal(const IfcValue& nominal, double length_scale, double area_scale,
                  double volume_scale, PropValue& prop) {
  const IfcValue* inner = &nominal;
  if (nominal.kind == IfcValue::Kind::Typed && !nominal.items.empty()) {
    prop.data_type = nominal.text;
    inner = &nominal.items[0];
  }
  if (inner->kind == IfcValue::Kind::String) {
    prop.value_text = inner->text;
    if (prop.data_type.empty()) prop.data_type = "string";
    return;
  }
  if (inner->kind == IfcValue::Kind::Enum) {
    if (inner->text == "T" || inner->text == "F" || inner->text == "U") {
      prop.data_type = "boolean";
      prop.value_text = inner->text == "T" ? "true" : inner->text == "F" ? "false" : "unknown";
      prop.has_num = inner->text != "U";
      prop.value_num = inner->text == "T" ? 1 : 0;
      return;
    }
    prop.value_text = inner->text;
    if (prop.data_type.empty()) prop.data_type = "enum";
    return;
  }
  if (inner->kind == IfcValue::Kind::Real || inner->kind == IfcValue::Kind::Integer) {
    double value = inner->real;
    const std::string& dtype = prop.data_type;
    if (dtype.find("VOLUMEMEASURE") != std::string::npos)
      value *= volume_scale;
    else if (dtype.find("AREAMEASURE") != std::string::npos)
      value *= area_scale;
    else if (dtype.find("LENGTHMEASURE") != std::string::npos)
      value *= length_scale;
    prop.has_num = true;
    prop.value_num = value;
    prop.value_text = format_num(value);
    if (prop.data_type.empty()) prop.data_type = "number";
  }
}

std::string material_name(const IfcFile& file, std::int64_t id) {
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr || entity->type != "IFCMATERIAL") return {};
  return str_at(*entity, 0);
}

void layers_from(const IfcFile& file, std::int64_t id, double length_scale,
                 std::vector<LayerValue>& layers, std::string& set_name, int depth) {
  if (id == 0 || depth > 8) return;
  const IfcEntity* entity = file.find(id);
  if (entity == nullptr) return;
  if (entity->type == "IFCMATERIAL") {
    LayerValue layer;
    layer.material = str_at(*entity, 0);
    layers.push_back(layer);
    return;
  }
  if (entity->type == "IFCMATERIALLIST") {
    for (std::int64_t mid : refs_of(attr(*entity, 0)))
      layers_from(file, mid, length_scale, layers, set_name, depth + 1);
    return;
  }
  if (entity->type == "IFCMATERIALLAYER") {
    LayerValue layer;
    layer.material = material_name(file, ref_at(*entity, 0));
    double thickness = 0;
    if (num_at(*entity, 1, thickness)) {
      layer.has_thickness = true;
      layer.thickness_m = thickness * length_scale;
    }
    layers.push_back(layer);
    return;
  }
  if (entity->type == "IFCMATERIALLAYERSET") {
    if (set_name.empty()) set_name = str_at(*entity, 1);
    for (std::int64_t lid : refs_of(attr(*entity, 0)))
      layers_from(file, lid, length_scale, layers, set_name, depth + 1);
    return;
  }
  if (entity->type == "IFCMATERIALLAYERSETUSAGE") {
    layers_from(file, ref_at(*entity, 0), length_scale, layers, set_name, depth + 1);
    return;
  }
  if (entity->type == "IFCMATERIALCONSTITUENTSET") {
    if (set_name.empty()) set_name = str_at(*entity, 1);
    for (std::int64_t cid : refs_of(attr(*entity, 0))) {
      const IfcEntity* constituent = file.find(cid);
      if (constituent == nullptr) continue;
      layers_from(file, ref_at(*constituent, 2), length_scale, layers, set_name, depth + 1);
    }
  }
}

std::string last_enum(const IfcEntity& entity) {
  for (int index = static_cast<int>(entity.attrs.size()) - 1; index >= 0; --index) {
    if (entity.attrs[static_cast<std::size_t>(index)].kind == IfcValue::Kind::Enum) {
      return entity.attrs[static_cast<std::size_t>(index)].text;
    }
  }
  return {};
}

}  // namespace

Scene build_scene(const IfcFile& file, const ConvertOptions& options, const std::string& ifc_text) {
  Scene scene;
  scene.schema = file.schema.empty() ? "IFC4" : file.schema;
  bool saw_area = false;
  bool saw_volume = false;
  for (const IfcEntity* unit : file.typed("IFCSIUNIT")) {
    const std::string kind = enum_at(*unit, 1);
    const std::string prefix = enum_at(*unit, 2);
    const std::string name = enum_at(*unit, 3);
    const double scale = prefix_scale(prefix);
    if (kind == "LENGTHUNIT") {
      scene.length_scale = scale;
      scene.length_unit_name = length_unit_name(prefix, name);
    } else if (kind == "AREAUNIT") {
      scene.area_scale = scale;
      saw_area = true;
    } else if (kind == "VOLUMEUNIT") {
      scene.volume_scale = scale;
      saw_volume = true;
    }
  }
  if (!saw_area) scene.area_scale = scene.length_scale * scene.length_scale;
  if (!saw_volume) scene.volume_scale = scene.area_scale * scene.length_scale;

  if (!file.typed("IFCPROJECT").empty())
    scene.project_name = str_at(*file.typed("IFCPROJECT")[0], 2);
  if (scene.project_name.empty()) scene.project_name = "Untitled";

  struct SpatialSeed {
    const IfcEntity* entity;
    std::string kind;
    int rank;
  };
  std::vector<SpatialSeed> seeds;
  const auto add_kind = [&](const char* type, const char* kind, int rank) {
    for (const IfcEntity* entity : file.typed(type)) seeds.push_back({entity, kind, rank});
  };
  add_kind("IFCPROJECT", "Project", 0);
  add_kind("IFCSITE", "Site", 1);
  add_kind("IFCBUILDING", "Building", 2);
  add_kind("IFCBUILDINGSTOREY", "Storey", 3);
  add_kind("IFCSPACE", "Space", 4);
  std::sort(seeds.begin(), seeds.end(), [](const SpatialSeed& a, const SpatialSeed& b) {
    if (a.rank != b.rank) return a.rank < b.rank;
    return a.entity->id < b.entity->id;
  });
  std::unordered_map<std::int64_t, std::size_t> spatial_index;
  for (const SpatialSeed& seed : seeds) {
    SpatialNode node;
    node.ifc_id = seed.entity->id;
    node.id = static_cast<std::int64_t>(scene.spatial.size() + 1);
    node.kind = seed.kind;
    node.name = str_at(*seed.entity, 2);
    if (seed.kind == "Storey") {
      double elevation = 0;
      if (num_at(*seed.entity, 9, elevation)) {
        node.has_elevation = true;
        node.elevation_m = elevation * scene.length_scale;
      }
    }
    spatial_index[node.ifc_id] = scene.spatial.size();
    scene.spatial.push_back(node);
  }
  for (const IfcEntity* rel : file.typed("IFCRELAGGREGATES")) {
    const std::int64_t parent = ref_at(*rel, 4);
    if (!spatial_index.count(parent)) continue;
    for (std::int64_t child : refs_of(attr(*rel, 5))) {
      const auto it = spatial_index.find(child);
      if (it != spatial_index.end()) scene.spatial[it->second].parent_ifc = parent;
    }
  }
  for (SpatialNode& node : scene.spatial) {
    const auto it = spatial_index.find(node.parent_ifc);
    if (it != spatial_index.end()) node.parent_id = scene.spatial[it->second].id;
  }

  std::vector<const IfcEntity*> products;
  for (const auto& entry : file.by_type) {
    for (std::int64_t id : entry.second) {
      const IfcEntity* entity = file.find(id);
      if (entity != nullptr && looks_like_product(*entity)) products.push_back(entity);
    }
  }
  std::sort(products.begin(), products.end(),
            [](const IfcEntity* a, const IfcEntity* b) { return a->id < b->id; });

  std::unordered_map<std::int64_t, std::int64_t> element_to_type;
  std::set<std::int64_t> type_ids;
  for (const IfcEntity* rel : file.typed("IFCRELDEFINESBYTYPE")) {
    const std::int64_t type_id = ref_at(*rel, 5);
    if (type_id == 0) continue;
    type_ids.insert(type_id);
    for (std::int64_t id : refs_of(attr(*rel, 4))) element_to_type[id] = type_id;
  }
  std::unordered_map<std::int64_t, std::size_t> type_index;
  for (std::int64_t type_id : type_ids) {
    const IfcEntity* entity = file.find(type_id);
    if (entity == nullptr) continue;
    TypeInfo info;
    info.ifc_id = type_id;
    info.row_id = static_cast<std::int64_t>(scene.types.size() + 1);
    info.guid = str_at(*entity, 0);
    info.ifc_class = class_name(entity->type);
    info.name = str_at(*entity, 2);
    info.predefined = last_enum(*entity);
    type_index[type_id] = scene.types.size();
    scene.types.push_back(std::move(info));
  }

  std::unordered_map<std::int64_t, std::size_t> element_index;
  for (const IfcEntity* product : products) {
    const std::string nice = class_name(product->type);
    if (!class_allowed(options.class_filter, nice) &&
        !class_allowed(options.class_filter, product->type))
      continue;
    Element element;
    element.ifc_id = product->id;
    element.id = static_cast<std::int64_t>(scene.elements.size() + 1);
    element.guid = str_at(*product, 0);
    element.ifc_class = nice;
    element.name = str_at(*product, 2);
    element.tag = str_at(*product, 7);
    element.has_representation = ref_at(*product, 6) != 0;
    const auto type_it = element_to_type.find(product->id);
    if (type_it != element_to_type.end()) element.type_ifc = type_it->second;
    set_color(element);
    element_index[element.ifc_id] = scene.elements.size();
    scene.elements.push_back(std::move(element));
  }

  std::unordered_map<std::int64_t, std::int64_t> container;
  for (const IfcEntity* rel : file.typed("IFCRELCONTAINEDINSPATIALSTRUCTURE")) {
    const std::int64_t structure = ref_at(*rel, 5);
    for (std::int64_t id : refs_of(attr(*rel, 4))) {
      if (!container.count(id)) container[id] = structure;
    }
  }
  const auto storey_of = [&](std::int64_t spatial_ifc) {
    for (int guard = 0; spatial_ifc != 0 && guard < 32; ++guard) {
      const auto it = spatial_index.find(spatial_ifc);
      if (it == spatial_index.end()) return std::int64_t{0};
      const SpatialNode& node = scene.spatial[it->second];
      if (node.kind == "Storey") return node.id;
      spatial_ifc = node.parent_ifc;
    }
    return std::int64_t{0};
  };
  for (Element& element : scene.elements) {
    const auto it = container.find(element.ifc_id);
    if (it == container.end()) continue;
    const auto spatial_it = spatial_index.find(it->second);
    if (spatial_it != spatial_index.end()) element.parent_id = scene.spatial[spatial_it->second].id;
    element.storey_id = storey_of(it->second);
  }

  const auto attach_pset = [&](std::int64_t target, Pset pset) {
    const auto element_it = element_index.find(target);
    if (element_it != element_index.end()) {
      pset.source = "instance";
      scene.elements[element_it->second].psets.push_back(std::move(pset));
      return;
    }
    const auto type_it = type_index.find(target);
    if (type_it != type_index.end()) {
      pset.source = "type";
      scene.types[type_it->second].psets.push_back(std::move(pset));
    }
  };

  for (const IfcEntity* rel : file.typed("IFCRELDEFINESBYPROPERTIES")) {
    const IfcEntity* definition = file.find(ref_at(*rel, 5));
    if (definition == nullptr) continue;
    const std::vector<std::int64_t> targets = refs_of(attr(*rel, 4));
    if (definition->type == "IFCPROPERTYSET") {
      Pset pset;
      pset.name = str_at(*definition, 2);
      for (std::int64_t prop_id : refs_of(attr(*definition, 4))) {
        const IfcEntity* prop_entity = file.find(prop_id);
        if (prop_entity == nullptr || prop_entity->type != "IFCPROPERTYSINGLEVALUE") {
          if (prop_entity != nullptr) {
            scene.warnings.push_back("skipped " + prop_entity->type + " in property set " +
                                     pset.name);
          }
          continue;
        }
        PropValue prop;
        prop.name = str_at(*prop_entity, 0);
        if (const IfcValue* nominal = attr(*prop_entity, 2)) {
          if (nominal->kind != IfcValue::Kind::Null) {
            read_nominal(*nominal, scene.length_scale, scene.area_scale, scene.volume_scale, prop);
          }
        }
        pset.props.push_back(std::move(prop));
      }
      for (std::int64_t target : targets) attach_pset(target, pset);
    } else if (definition->type == "IFCELEMENTQUANTITY") {
      const std::string qset = str_at(*definition, 2);
      std::vector<QuantityValue> quantities;
      for (std::int64_t qid : refs_of(attr(*definition, 5))) {
        const IfcEntity* quantity = file.find(qid);
        if (quantity == nullptr) continue;
        QuantityValue value;
        value.qset = qset;
        value.name = str_at(*quantity, 0);
        double raw = 0;
        if (!num_at(*quantity, 3, raw)) continue;
        if (quantity->type == "IFCQUANTITYLENGTH") {
          value.kind = "Length";
          value.unit = "m";
          value.value = raw * scene.length_scale;
        } else if (quantity->type == "IFCQUANTITYAREA") {
          value.kind = "Area";
          value.unit = "m2";
          value.value = raw * scene.area_scale;
        } else if (quantity->type == "IFCQUANTITYVOLUME") {
          value.kind = "Volume";
          value.unit = "m3";
          value.value = raw * scene.volume_scale;
        } else if (quantity->type == "IFCQUANTITYCOUNT") {
          value.kind = "Count";
          value.unit = "1";
          value.value = raw;
        } else if (quantity->type == "IFCQUANTITYWEIGHT") {
          value.kind = "Weight";
          value.unit = "kg";
          value.value = raw;
        } else {
          scene.warnings.push_back("skipped quantity " + quantity->type);
          continue;
        }
        quantities.push_back(value);
      }
      for (std::int64_t target : targets) {
        const auto element_it = element_index.find(target);
        if (element_it != element_index.end()) {
          auto& dest = scene.elements[element_it->second].quantities;
          dest.insert(dest.end(), quantities.begin(), quantities.end());
          continue;
        }
        if (type_index.count(target)) {
          for (Element& element : scene.elements) {
            if (element.type_ifc == target) {
              element.quantities.insert(element.quantities.end(), quantities.begin(),
                                        quantities.end());
            }
          }
        }
      }
    }
  }

  for (const IfcEntity* rel : file.typed("IFCRELASSOCIATESMATERIAL")) {
    std::vector<LayerValue> layers;
    std::string set_name;
    layers_from(file, ref_at(*rel, 5), scene.length_scale, layers, set_name, 0);
    if (layers.empty()) continue;
    const auto apply = [&](Element& element) {
      element.layers = layers;
      element.material_set_name = set_name;
    };
    for (std::int64_t target : refs_of(attr(*rel, 4))) {
      const auto element_it = element_index.find(target);
      if (element_it != element_index.end()) {
        apply(scene.elements[element_it->second]);
        continue;
      }
      if (type_index.count(target)) {
        for (Element& element : scene.elements) {
          if (element.type_ifc == target) apply(element);
        }
      }
    }
  }

  for (const IfcEntity* rel : file.typed("IFCRELASSOCIATESCLASSIFICATION")) {
    const IfcEntity* ref = file.find(ref_at(*rel, 5));
    if (ref == nullptr || ref->type != "IFCCLASSIFICATIONREFERENCE") continue;
    ClassifValue value;
    value.code = str_at(*ref, 1);
    value.title = str_at(*ref, 2);
    if (const IfcEntity* system = file.find(ref_at(*ref, 3))) {
      if (system->type == "IFCCLASSIFICATION") value.system = str_at(*system, 3);
    }
    for (std::int64_t target : refs_of(attr(*rel, 4))) {
      const auto element_it = element_index.find(target);
      if (element_it != element_index.end())
        scene.elements[element_it->second].classes.push_back(value);
    }
  }

  const auto geometry_started = std::chrono::steady_clock::now();
  if (options.mesher != "analytic") apply_ifcopenshell_geometry(scene, ifc_text, options);
  if (!scene.ifcopenshell_ran && !file.typed("IFCOPENINGELEMENT").empty()) {
    scene.warnings.push_back(
        "IfcOpeningElement is recorded but not subtracted; the analytic mesher does not evaluate "
        "booleans");
  }

  bool analytic_used = false;
  for (Element& element : scene.elements) {
    if (element.has_mesh) continue;
    if (!element.has_representation) {
      std::ostringstream line;
      line << "element " << element.ifc_class << " '" << element.name << "' " << element.guid
           << " has no representation";
      scene.warnings.push_back(line.str());
      ++scene.without_geometry;
      continue;
    }
    const IfcEntity* product = file.find(element.ifc_id);
    std::string why;
    if (product != nullptr && mesh_product(file, *product, scene.length_scale, element.mesh, why)) {
      element.has_mesh = true;
      element.mesh_source = "analytic-extrusion-v1";
      element.geometry_failure.clear();
      analytic_used = true;
      scene.notes.push_back("fallback: " + element.guid + " " + element.ifc_class +
                            " meshed by analytic-extrusion");
    } else {
      std::ostringstream line;
      line << "failed: " << element.ifc_class << " '" << element.name << "' " << element.guid;
      if (!element.geometry_failure.empty()) line << ": " << element.geometry_failure;
      if (!why.empty()) {
        if (!element.geometry_failure.empty())
          line << "; analytic: " << why;
        else
          line << ": " << why;
      }
      if (element.geometry_failure.empty() && why.empty()) line << ": no supported solid";
      scene.warnings.push_back(line.str());
      ++scene.failed;
    }
  }
  if (scene.ifcopenshell_ran && analytic_used)
    scene.mesh_generator = "ifcopenshell-occt+analytic-extrusion-v1";
  else if (scene.ifcopenshell_ran)
    scene.mesh_generator = "ifcopenshell-occt";
  else
    scene.mesh_generator = "analytic-extrusion-v1";

  for (Element& element : scene.elements) {
    if (!element.has_mesh) continue;
    for (std::size_t i = 0; i + 2 < element.mesh.position.size(); i += 3) {
      expand_bbox(element, {element.mesh.position[i], element.mesh.position[i + 1],
                            element.mesh.position[i + 2]});
    }
  }
  scene.geometry_seconds =
      std::chrono::duration<double>(std::chrono::steady_clock::now() - geometry_started).count();

  for (const Element& element : scene.elements) {
    if (!element.has_bbox) continue;
    if (!scene.has_world) {
      for (int axis = 0; axis < 3; ++axis) {
        scene.world_min[axis] = element.bbox_min[axis];
        scene.world_max[axis] = element.bbox_max[axis];
      }
      scene.has_world = true;
    } else {
      for (int axis = 0; axis < 3; ++axis) {
        scene.world_min[axis] = std::min(scene.world_min[axis], element.bbox_min[axis]);
        scene.world_max[axis] = std::max(scene.world_max[axis], element.bbox_max[axis]);
      }
    }
  }
  if (scene.has_world) {
    scene.origin = {scene.world_min[0], scene.world_min[1], scene.world_min[2]};
    for (Element& element : scene.elements) {
      if (!element.has_mesh) continue;
      for (std::size_t i = 0; i < element.mesh.position.size(); i += 3) {
        element.mesh.position[i] -= scene.origin.x;
        element.mesh.position[i + 1] -= scene.origin.y;
        element.mesh.position[i + 2] -= scene.origin.z;
      }
    }
  }
  return scene;
}

}  // namespace fbv
