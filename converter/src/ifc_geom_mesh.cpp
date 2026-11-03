#include "ifc_geom_mesh.hpp"

#include "mesh_stream.hpp"

#include <algorithm>
#include <cctype>
#include <limits>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <utility>

#if defined(FBV_WITH_IFCOPENSHELL)
#include <filesystem>
#include <memory>
#include <thread>

#include "ifcgeom/Iterator.h"
#include "ifcgeom/hybrid_kernel.h"
#include "ifcparse/IfcFile.h"
#include "ifcparse/IfcLogger.h"
#endif

namespace fbv {
namespace {

#if defined(FBV_WITH_IFCOPENSHELL)

std::string upper_copy(std::string text) {
  for (char& c : text) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
  return text;
}

bool allowed_class(const std::vector<std::string>& filter, const std::string& ifc_class) {
  if (filter.empty()) return true;
  const std::string cur = upper_copy(ifc_class);
  for (const std::string& item : filter) {
    if (upper_copy(item) == cur) return true;
  }
  return false;
}

int thread_count(const ConvertOptions& options) {
  int n = 0;
  if (options.threads > 0) {
    n = options.threads;
  } else {
    const unsigned hc = std::thread::hardware_concurrency();
    n = hc == 0 ? 2 : static_cast<int>(hc);
  }
  if (options.max_threads > 0) n = std::min(n, options.max_threads);
  if (options.max_memory_mb >= 0) {
    // One in-flight Open CASCADE shape is large. Stay at two workers below 512 MiB
    // so a tight cap does not serialize the iterator (one thread aborts on the first
    // failed element).
    const int cap = options.max_memory_mb < 512 ? 2 : std::max(2, options.max_memory_mb / 512);
    n = std::min(n, cap);
  }
  if (n < 1) n = 1;
  const bool asked_for_one = options.threads == 1 || options.max_threads == 1;
  if (n < 2 && !asked_for_one) n = 2;
  return n;
}

std::string guid_of(IfcUtil::IfcBaseEntity* entity) {
  try {
    return entity->get_value<std::string>("GlobalId");
  } catch (const std::exception&) {
    return {};
  }
}

std::string text_attr(IfcUtil::IfcBaseEntity* entity, const char* name) {
  try {
    return entity->get_value<std::string>(name, std::string());
  } catch (const std::exception&) {
    return {};
  }
}

void copy_triangulation(const IfcGeom::Representation::Triangulation& geometry, TriMesh& mesh) {
  const std::vector<double>& verts = geometry.verts();
  const std::vector<int>& faces = geometry.faces();
  const std::size_t vert_count = verts.size() / 3;
  for (std::size_t i = 0; i + 2 < faces.size(); i += 3) {
    const int ia = faces[i];
    const int ib = faces[i + 1];
    const int ic = faces[i + 2];
    if (ia < 0 || ib < 0 || ic < 0) continue;
    const auto a = static_cast<std::size_t>(ia);
    const auto b = static_cast<std::size_t>(ib);
    const auto c = static_cast<std::size_t>(ic);
    if (a >= vert_count || b >= vert_count || c >= vert_count) continue;
    const Vec3 pa{verts[a * 3], verts[a * 3 + 1], verts[a * 3 + 2]};
    const Vec3 pb{verts[b * 3], verts[b * 3 + 1], verts[b * 3 + 2]};
    const Vec3 pc{verts[c * 3], verts[c * 3 + 1], verts[c * 3 + 2]};
    add_triangle(mesh, pa, pb, pc);
  }
}

std::string fresh_log() {
  // Logger keeps one process-wide buffer. Keep only the text appended by this call.
  static std::size_t mark = 0;
  const std::string full = Logger::GetLog();
  const std::string fresh = full.size() >= mark ? full.substr(mark) : full;
  mark = full.size();
  return fresh;
}

std::string reason_for(const std::string& log, const std::string& guid,
                       const std::string& step_id) {
  std::string reason = "IfcOpenShell produced no triangulation";
  if (log.empty()) return reason;
  std::istringstream lines(log);
  std::string line;
  std::string extra;
  while (std::getline(lines, line)) {
    if ((!guid.empty() && line.find(guid) != std::string::npos) ||
        (!step_id.empty() && line.find("#" + step_id) != std::string::npos)) {
      if (!extra.empty()) extra.push_back(' ');
      extra += line;
      if (extra.size() > 400) break;
    }
  }
  if (!extra.empty()) reason += " (" + extra + ")";
  return reason;
}

#endif

}  // namespace

void apply_ifcopenshell_geometry(Scene& scene, const std::string& ifc_text,
                                 const ConvertOptions& options) {
#if !defined(FBV_WITH_IFCOPENSHELL)
  (void)ifc_text;
  if (options.mesher == "ifcopenshell") scene.ios_unavailable = true;
  return;
#else
  scene.threads = thread_count(options);
  scene.geometry_library = "opencascade";
  try {
    std::istringstream memory_stream;
    std::unique_ptr<IfcParse::IfcFile> model;
    if (!options.input_path.empty() && std::filesystem::is_regular_file(options.input_path)) {
      model.reset(new IfcParse::IfcFile(options.input_path));
    } else {
      if (ifc_text.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        scene.ifc_log =
            "IfcOpenShell's memory loader rejects IFC text larger than 2 GiB; convert the file "
            "by path so the iterator can read it from disk.\n";
        return;
      }
      memory_stream.str(ifc_text);
      model.reset(new IfcParse::IfcFile(memory_stream, static_cast<int>(ifc_text.size())));
    }
    if (!model->good()) {
      scene.ifc_log =
          "IfcOpenShell could not parse the file (unsupported schema or syntax). The analytic "
          "mesher will run.\n";
      return;
    }

    std::ostream* log_out = nullptr;
    Logger::SetOutput(log_out, log_out);
    Logger::Verbosity(Logger::LOG_NOTICE);

    std::unordered_map<std::int64_t, std::size_t> by_step;
    std::unordered_set<std::string> have_guid;
    for (std::size_t i = 0; i < scene.elements.size(); ++i) {
      by_step[scene.elements[i].ifc_id] = i;
      if (!scene.elements[i].guid.empty()) have_guid.insert(scene.elements[i].guid);
    }

    aggregate_of_instance::ptr products = model->instances_by_type("IfcElement");
    if (products) {
      for (auto it = products->begin(); it != products->end(); ++it) {
        IfcUtil::IfcBaseClass* inst = *it;
        if (inst == nullptr) continue;
        auto* entity = inst->as<IfcUtil::IfcBaseEntity>();
        if (entity == nullptr) continue;
        const std::string type = entity->declaration().name();
        const std::string guid = guid_of(entity);
        if (!allowed_class(options.class_filter, type)) {
          ++scene.excluded;
          continue;
        }
        const auto step = static_cast<std::int64_t>(entity->id());
        const auto found = by_step.find(step);
        if (found != by_step.end()) {
          if (!type.empty()) scene.elements[found->second].ifc_class = type;
          if (!guid.empty()) have_guid.insert(guid);
          continue;
        }
        Element element;
        element.ifc_id = step;
        element.id = static_cast<std::int64_t>(scene.elements.size() + 1);
        element.guid = guid;
        element.ifc_class = type.empty() ? "IfcElement" : type;
        element.name = text_attr(entity, "Name");
        element.tag = text_attr(entity, "Tag");
        element.has_representation = true;
        scene.notes.push_back("recovered " + element.ifc_class + " " + element.guid +
                              " from IfcOpenShell; the attribute pass had not listed it");
        by_step[step] = scene.elements.size();
        if (!guid.empty()) have_guid.insert(guid);
        scene.elements.push_back(std::move(element));
      }
    }
    if (products) {
      for (auto it = products->begin(); it != products->end(); ++it) {
        IfcUtil::IfcBaseClass* inst = *it;
        if (inst == nullptr) continue;
        auto* entity = inst->as<IfcUtil::IfcBaseEntity>();
        if (entity == nullptr) continue;
        const std::string type = entity->declaration().name();
        if (!allowed_class(options.class_filter, type)) continue;
        const std::string guid = guid_of(entity);
        if (!guid.empty() && !have_guid.count(guid)) scene.missing_guids.push_back(guid);
      }
    }
    scene.completeness_ok = scene.missing_guids.empty();

    ifcopenshell::geometry::Settings settings;
    settings.get<ifcopenshell::geometry::settings::UseWorldCoords>().value = true;
    settings.get<ifcopenshell::geometry::settings::ConvertBackUnits>().value = false;
    settings.get<ifcopenshell::geometry::settings::MesherLinearDeflection>().value =
        options.linear_deflection_m;
    settings.get<ifcopenshell::geometry::settings::MesherAngularDeflection>().value =
        options.angular_deflection_rad;
    settings.get<ifcopenshell::geometry::settings::WeldVertices>().value = true;
    settings.get<ifcopenshell::geometry::settings::ApplyDefaultMaterials>().value = true;
    settings.get<ifcopenshell::geometry::settings::IteratorOutput>().value =
        ifcopenshell::geometry::settings::TRIANGULATED;

    IfcGeom::Iterator iterator(
        ifcopenshell::geometry::kernels::construct(model.get(), "opencascade", settings), settings,
        model.get(), std::vector<IfcGeom::filter_t>{}, scene.threads);
    scene.ifcopenshell_ran = true;
    if (!iterator.initialize()) {
      scene.ifc_log = fresh_log();
      if (scene.ifc_log.empty()) {
        scene.ifc_log = "IfcOpenShell iterator initialized no geometrical elements.\n";
      }
    } else {
      do {
        IfcGeom::Element* geom = iterator.get();
        if (geom == nullptr) break;
        auto* tri = static_cast<IfcGeom::TriangulationElement*>(geom);
        const auto step = static_cast<std::int64_t>(tri->id());
        const auto found = by_step.find(step);
        if (found == by_step.end()) continue;
        Element& element = scene.elements[found->second];
        if (element.mesh.position.empty() && !element.mesh_scratch.empty())
          reload_mesh_world(scene, element);
        const std::size_t before = element.mesh.indices.size();
        copy_triangulation(tri->geometry(), element.mesh);
        if (element.mesh.indices.size() > before) {
          element.has_mesh = true;
          element.mesh_source = "ifcopenshell-occt";
          element.geometry_failure.clear();
          element.failure_reason.clear();
          commit_mesh(scene, element, options);
        }
      } while (iterator.next());
      scene.ifc_log = fresh_log();
      std::ostringstream unit;
      unit << "ifcopenshell length unit " << iterator.unit_name() << " magnitude "
           << iterator.unit_magnitude() << "\n";
      scene.ifc_log += unit.str();
    }

    for (Element& element : scene.elements) {
      if (element.has_mesh || !element.has_representation) continue;
      if (!element.geometry_failure.empty()) continue;
      element.geometry_failure =
          reason_for(scene.ifc_log, element.guid, std::to_string(element.ifc_id));
    }
  } catch (const std::exception& ex) {
    for (Element& element : scene.elements) {
      if (element.mesh_source == "ifcopenshell-occt") discard_element_mesh(scene, element);
    }
    scene.ifcopenshell_ran = false;
    scene.geometry_library = "analytic";
    scene.ifc_log = std::string("IfcOpenShell geometry failed: ") + ex.what() +
                    "\nThe analytic mesher will run.\n";
  }
#endif
}

}  // namespace fbv
