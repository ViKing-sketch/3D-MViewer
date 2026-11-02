#include "fbv/convert.hpp"

#include "ifc_parse.hpp"
#include "scene.hpp"
#include "write_pkg.hpp"
#include "xde_import.hpp"

#include "fbv/io.hpp"
#include "fbv/json.hpp"
#include "fbv_version.h"

#include <chrono>
#include <filesystem>
#include <sstream>

#if defined(_WIN32)
#include <windows.h>
#include <psapi.h>
#elif defined(__linux__) || defined(__APPLE__)
#include <sys/resource.h>
#endif

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

std::uint64_t peak_rss_bytes() {
#if defined(_WIN32)
  PROCESS_MEMORY_COUNTERS counters;
  if (GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters)))
    return counters.PeakWorkingSetSize;
  return 0;
#elif defined(__linux__)
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage) != 0) return 0;
  return static_cast<std::uint64_t>(usage.ru_maxrss) * 1024ull;
#elif defined(__APPLE__)
  struct rusage usage;
  if (getrusage(RUSAGE_SELF, &usage) != 0) return 0;
  return static_cast<std::uint64_t>(usage.ru_maxrss);
#else
  return 0;
#endif
}

std::uint64_t path_bytes(const std::filesystem::path& path) {
  std::error_code ec;
  if (std::filesystem::is_regular_file(path, ec)) return std::filesystem::file_size(path, ec);
  std::uint64_t total = 0;
  if (!std::filesystem::is_directory(path, ec)) return 0;
  for (const auto& entry : std::filesystem::recursive_directory_iterator(path, ec)) {
    if (entry.is_regular_file()) total += static_cast<std::uint64_t>(entry.file_size());
  }
  return total;
}

double seconds_between(std::chrono::steady_clock::time_point a,
                       std::chrono::steady_clock::time_point b) {
  return std::chrono::duration<double>(b - a).count();
}

void fill_status(ConvertStatus& status, const Scene& scene) {
  status.elements = static_cast<int>(scene.elements.size());
  status.with_mesh = mesh_count(scene);
  status.failed = scene.failed;
  status.without_geometry = scene.without_geometry;
  status.warnings = static_cast<int>(scene.warnings.size());
  status.triangles = scene.triangles;
  status.threads = scene.threads;
  status.geometry_seconds = scene.geometry_seconds;
  status.mesher = scene.mesh_generator;
  status.schema = scene.schema;
  status.completeness_ok = scene.completeness_ok;
  status.peak_rss_bytes = peak_rss_bytes();
}

std::string summary_json(const ConvertStatus& status, const ConvertOptions& options,
                         const Scene* scene) {
  Json root = Json::object();
  root.set("tool", Json::string("fbvconv"));
  root.set("version", Json::string(FBV_VERSION_STRING));
  root.set("input",
           Json::string(options.input_path.empty() ? options.source_name : options.input_path));
  root.set("output", Json::string(options.output));
  root.set("schema", Json::string(status.schema));
  root.set("mesher", Json::string(status.mesher));
  root.set("geometry_kernel",
           Json::string(scene != nullptr ? scene->geometry_library : "analytic"));
  root.set("threads", Json::integer(status.threads));
  root.set("elements", Json::integer(status.elements));
  root.set("with_mesh", Json::integer(status.with_mesh));
  root.set("failed", Json::integer(status.failed));
  root.set("without_geometry", Json::integer(status.without_geometry));
  root.set("excluded", Json::integer(scene != nullptr ? scene->excluded : 0));
  root.set("triangles", Json::integer(status.triangles));
  root.set("warnings", Json::integer(status.warnings));
  root.set("completeness", Json::string(status.completeness_ok ? "ok" : "incomplete"));
  Json missing = Json::array();
  if (scene != nullptr) {
    for (const std::string& guid : scene->missing_guids) missing.push(Json::string(guid));
  }
  root.set("missing_guids", std::move(missing));
  root.set("package_bytes", Json::integer(static_cast<std::int64_t>(status.package_bytes)));
  root.set("peak_rss_bytes", Json::integer(static_cast<std::int64_t>(status.peak_rss_bytes)));
  Json timings = Json::object();
  timings.set("parse", Json::real(status.parse_seconds));
  timings.set("geometry", Json::real(status.geometry_seconds));
  timings.set("write", Json::real(status.write_seconds));
  timings.set("total", Json::real(status.total_seconds));
  root.set("timings_s", std::move(timings));
  root.set("code", Json::integer(status.code));
  root.set("error", Json::string(status.error));
  return root.dump(2) + "\n";
}

void emit_json(ConvertStatus& status, const ConvertOptions& options, const Scene* scene) {
  if (options.json_output.empty()) return;
  const std::string body = summary_json(status, options, scene);
  if (options.json_output == "-") {
    status.json_body = body;
    status.json_path = "-";
    return;
  }
  write_text(options.json_output, body);
  status.json_path = options.json_output;
}

std::string render_log(const Scene& scene, const ConvertStatus& status) {
  std::ostringstream log;
  log << "fbvconv " << scene.mesh_generator << "\n";
  log << "schema: " << scene.schema << "\n";
  log << "length unit: " << scene.length_unit_name << "\n";
  log << "geometry_kernel: " << scene.geometry_library << "\n";
  log << "threads: " << scene.threads << "\n";
  log << "elements: " << status.elements << "\n";
  log << "with_mesh: " << status.with_mesh << "\n";
  log << "failed: " << status.failed << "\n";
  log << "without_geometry: " << status.without_geometry << "\n";
  log << "excluded: " << scene.excluded << "\n";
  log << "triangles: " << status.triangles << "\n";
  log << "completeness: " << (scene.completeness_ok ? "ok" : "incomplete") << "\n";
  log << "peak_rss_bytes: " << status.peak_rss_bytes << "\n";
  log << "package_bytes: " << status.package_bytes << "\n";
  log << "parse_s: " << status.parse_seconds << "\n";
  log << "geometry_s: " << status.geometry_seconds << "\n";
  log << "write_s: " << status.write_seconds << "\n";
  log << "total_s: " << status.total_seconds << "\n";
  log << "Deflection is applied by the Open CASCADE mesher when IfcOpenShell is linked. "
         "The analytic fallback emits prism faces for extrusions it understands.\n";
  for (const std::string& guid : scene.missing_guids) log << "missing: " << guid << "\n";
  for (const std::string& note : scene.notes) log << "note: " << note << "\n";
  for (const std::string& warning : scene.warnings) log << "warning: " << warning << "\n";
  if (!scene.ifc_log.empty()) {
    log << "ifcopenshell:\n" << scene.ifc_log;
    if (scene.ifc_log.back() != '\n') log << "\n";
  }
  return log.str();
}

}  // namespace

ConvertStatus convert_text(const std::string& ifc_text, const ConvertOptions& options) {
  ConvertStatus status;
  const auto total_started = std::chrono::steady_clock::now();
  Scene scene;
  bool have_scene = false;
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
    const auto parse_started = std::chrono::steady_clock::now();
    const IfcFile file = parse_ifc(ifc_text);
    if (file.schema.find("IFC") == std::string::npos) {
      status.code = 2;
      status.error = XdeImportStatus{}.error + " (schema " + file.schema + ")";
      status.total_seconds = seconds_between(total_started, std::chrono::steady_clock::now());
      emit_json(status, options, nullptr);
      return status;
    }
    scene = build_scene(file, options, ifc_text);
    have_scene = true;
    const auto parsed = std::chrono::steady_clock::now();
    status.parse_seconds = seconds_between(parse_started, parsed) - scene.geometry_seconds;
    if (status.parse_seconds < 0) status.parse_seconds = 0;
    if (scene.ios_unavailable) {
      status.code = 2;
      status.error =
          "this fbvconv build has no IfcOpenShell geometry; configure with "
          "-DFBV_WITH_IFCOPENSHELL=ON";
      fill_status(status, scene);
      status.total_seconds = seconds_between(total_started, std::chrono::steady_clock::now());
      if (!options.output.empty()) {
        status.log_path = log_for(options);
        write_text(status.log_path, render_log(scene, status));
      }
      emit_json(status, options, &scene);
      return status;
    }
    if (!scene.completeness_ok && !options.allow_incomplete) {
      status.code = 4;
      std::ostringstream message;
      message << "conversion incomplete: " << scene.missing_guids.size()
              << " source elements are missing from the package (pass --allow-incomplete to write "
                 "it anyway)";
      status.error = message.str();
      fill_status(status, scene);
      status.total_seconds = seconds_between(total_started, std::chrono::steady_clock::now());
      status.log_path = log_for(options);
      write_text(status.log_path, render_log(scene, status));
      emit_json(status, options, &scene);
      return status;
    }
    if (options.lod > 1) {
      scene.warnings.push_back(
          "only lod0 is written; lod1/lod2 need meshoptimizer and are left for task Z10");
    }
    const std::string source_name = options.source_name.empty() ? "input.ifc" : options.source_name;
    const auto write_started = std::chrono::steady_clock::now();
    write_scene_package(scene, options, ifc_text, source_name);
    const auto write_done = std::chrono::steady_clock::now();
    status.write_seconds = seconds_between(write_started, write_done);
    status.package_bytes = path_bytes(options.output);
    fill_status(status, scene);
    status.total_seconds = seconds_between(total_started, std::chrono::steady_clock::now());
    status.log_path = log_for(options);
    write_text(status.log_path, render_log(scene, status));
    emit_json(status, options, &scene);
    status.code = 0;
  } catch (const std::exception& ex) {
    status.code = 2;
    status.error = ex.what();
    status.peak_rss_bytes = peak_rss_bytes();
    status.total_seconds = seconds_between(total_started, std::chrono::steady_clock::now());
    if (have_scene) fill_status(status, scene);
    emit_json(status, options, have_scene ? &scene : nullptr);
  }
  return status;
}

ConvertStatus convert_file(const std::string& input_path, const ConvertOptions& options) {
  ConvertOptions copy = options;
  if (copy.source_name.empty())
    copy.source_name = std::filesystem::path(input_path).filename().string();
  copy.input_path = input_path;
  try {
    return convert_text(read_text(input_path), copy);
  } catch (const std::exception& ex) {
    ConvertStatus status;
    status.code = 2;
    status.error = ex.what();
    status.peak_rss_bytes = peak_rss_bytes();
    emit_json(status, copy, nullptr);
    return status;
  }
}

}  // namespace fbv
