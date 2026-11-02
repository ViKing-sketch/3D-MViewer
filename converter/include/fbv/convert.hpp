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
  double parse_seconds = 0;
  double geometry_seconds = 0;
  double write_seconds = 0;
  double total_seconds = 0;
  std::string mesher;
  std::string schema;
  bool completeness_ok = true;
  std::string json_body;
};

ConvertStatus convert_file(const std::string& input_path, const ConvertOptions& options);
ConvertStatus convert_text(const std::string& ifc_text, const ConvertOptions& options);

// 0 when the package is consistent, 3 when it is not. report is human-readable.
int validate_package(const std::string& path, std::string& report);

}  // namespace fbv
