#include "fbv/convert.hpp"

#include "ifc_parse.hpp"
#include "scene.hpp"
#include "write_pkg.hpp"
#include "xde_import.hpp"

#include "fbv/io.hpp"

#include <filesystem>
#include <sstream>

namespace fbv {
namespace {

std::string log_for(const ConvertOptions& options) {
  return options.output + ".log";
}

int mesh_count(const Scene& scene) {
  int count = 0;
  for (const Element& element : scene.elements) {
    if (element.has_mesh) ++count;
  }
  return count;
}

}  // namespace

ConvertStatus convert_text(const std::string& ifc_text, const ConvertOptions& options) {
  ConvertStatus status;
  try {
    if (options.output.empty()) throw std::runtime_error("output path is empty");
    std::size_t cursor = 0;
    if (ifc_text.size() >= 3 && static_cast<unsigned char>(ifc_text[0]) == 0xEF &&
        static_cast<unsigned char>(ifc_text[1]) == 0xBB &&
        static_cast<unsigned char>(ifc_text[2]) == 0xBF) {
      cursor = 3;
    }
    while (cursor < ifc_text.size() && (ifc_text[cursor] == ' ' || ifc_text[cursor] == '\n' ||
                                        ifc_text[cursor] == '\r' || ifc_text[cursor] == '\t')) {
      ++cursor;
    }
    if (ifc_text.compare(cursor, 12, "ISO-10303-21") != 0) {
      throw std::runtime_error("input is not an ISO-10303-21 file");
    }
    const IfcFile file = parse_ifc(ifc_text);
    if (file.schema.find("IFC") == std::string::npos) {
      status.code = 2;
      status.error = XdeImportStatus{}.error + " (schema " + file.schema + ")";
      return status;
    }
    Scene scene = build_scene(file, options.class_filter);
    if (options.lod > 1) {
      scene.warnings.push_back(
          "only lod0 is written; lod1/lod2 need meshoptimizer and are left for task Z10");
    }
    const std::string source_name = options.source_name.empty() ? "input.ifc" : options.source_name;
    write_scene_package(scene, options, ifc_text, source_name);
    std::ostringstream log;
    log << "fbvconv " << "analytic-extrusion-v1\n";
    log << "schema: " << scene.schema << "\n";
    log << "length unit: " << scene.length_unit_name << "\n";
    log << "elements: " << scene.elements.size() << "\n";
    log << "with_mesh: " << mesh_count(scene) << "\n";
    log << "Deflection values are stored in the manifest. The analytic mesher emits exact prism "
           "faces.\n";
    for (const std::string& warning : scene.warnings) log << "warning: " << warning << "\n";
    const std::string log_path = log_for(options);
    write_text(log_path, log.str());
    status.code = 0;
    status.log_path = log_path;
    status.elements = static_cast<int>(scene.elements.size());
    status.with_mesh = mesh_count(scene);
    status.warnings = static_cast<int>(scene.warnings.size());
  } catch (const std::exception& ex) {
    status.code = 2;
    status.error = ex.what();
  }
  return status;
}

ConvertStatus convert_file(const std::string& input_path, const ConvertOptions& options) {
  ConvertOptions copy = options;
  if (copy.source_name.empty())
    copy.source_name = std::filesystem::path(input_path).filename().string();
  try {
    return convert_text(read_text(input_path), copy);
  } catch (const std::exception& ex) {
    ConvertStatus status;
    status.code = 2;
    status.error = ex.what();
    return status;
  }
}

}  // namespace fbv
