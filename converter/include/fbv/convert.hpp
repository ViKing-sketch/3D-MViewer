#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace fbv {

struct ConvertOptions {
  std::string output;
  bool as_directory = false;
  bool write_brep = true;
  std::vector<std::string> class_filter;
  double linear_deflection_m = 0.01;
  double angular_deflection_rad = 0.5;
  int lod = 1;
  std::string source_name;
  // auto: IfcOpenShell when this build has it, otherwise analytic extrusion.
  // analytic: never call IfcOpenShell. ifcopenshell: require the OCCT kernel.
  std::string mesher = "auto";
  int threads = 0;
  // Caps --threads and the hardware default. 0 means no extra cap.
  // IfcOpenShell's single-thread iterator stops after the first failed element,
  // so a cap of 1 is honored only when it is set explicitly.
  int max_threads = 0;
  // Mesh bytes kept in RAM before the rest are flushed to disk.
  // -1 uses the 64 MiB default. 0 flushes every element.
  // Also limits Open CASCADE threads to about one per 512 MiB, and never below 2
  // unless --threads 1 or --max-threads 1 was requested.
  int max_memory_mb = -1;
  bool allow_incomplete = false;
  bool stats = false;
  std::string json_output;
  std::string input_path;
};

struct ConvertStatus {
  int code = 0;
  std::string error;
  std::string log_path;
  std::string json_path;
  int elements = 0;
  int with_mesh = 0;
  int failed = 0;
  int without_geometry = 0;
  int warnings = 0;
  int triangles = 0;
  int threads = 1;
  std::uint64_t package_bytes = 0;
  std::uint64_t peak_rss_bytes = 0;
  std::uint64_t mesh_bytes_peak = 0;
  double parse_seconds = 0;
  double geometry_seconds = 0;
  double write_seconds = 0;
  double total_seconds = 0;
  std::string mesher;
  std::string schema;
  bool completeness_ok = true;
  std::string json_body;
};

// Bytes of triangle data held in RAM before meshes are flushed to scratch files.
inline std::uint64_t mesh_budget_bytes(const ConvertOptions& options) {
  if (options.max_memory_mb < 0) return 64ull * 1024ull * 1024ull;
  return static_cast<std::uint64_t>(options.max_memory_mb) * 1024ull * 1024ull;
}

ConvertStatus convert_file(const std::string& input_path, const ConvertOptions& options);
ConvertStatus convert_text(const std::string& ifc_text, const ConvertOptions& options);

// 0 when the package is consistent, 3 when it is not. report is human-readable.
int validate_package(const std::string& path, std::string& report);

}  // namespace fbv
