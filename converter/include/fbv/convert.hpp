#pragma once

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
};

struct ConvertStatus {
  int code = 0;
  std::string error;
  std::string log_path;
  int elements = 0;
  int with_mesh = 0;
  int warnings = 0;
};

ConvertStatus convert_file(const std::string& input_path, const ConvertOptions& options);
ConvertStatus convert_text(const std::string& ifc_text, const ConvertOptions& options);

// 0 when the package is consistent, 3 when it is not. report is human-readable.
int validate_package(const std::string& path, std::string& report);

}  // namespace fbv
