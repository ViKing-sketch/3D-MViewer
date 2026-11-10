#pragma once

#include "fbv_core.h"

#include "fbv/json.hpp"
#include "fbv/sqlite_util.hpp"

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fbv {

struct OwnedTempDir {
  std::filesystem::path path;
  ~OwnedTempDir();
};

struct BrepBox {
  std::int64_t element_id = 0;
  double min_xyz[3]{};
  double max_xyz[3]{};
};

}  // namespace fbv

struct fbv_package {
  std::filesystem::path root;
  fbv::OwnedTempDir* temp = nullptr;
  fbv::Json manifest;
  fbv::SqliteDb db;
  std::string brep_codec;
  std::vector<fbv::BrepBox> brep_boxes;
  mutable std::string error;

  ~fbv_package();

  int manifest_info(fbv_manifest_info* out) const;
  int spatial_count();
  int spatial_at(int index, fbv_spatial_info* out);
  int element_count();
  int element_at(int index, fbv_element_info* out);
  int element_by_id(std::int64_t id, fbv_element_info* out);
  int prop_count(std::int64_t element_id);
  int prop_at(std::int64_t element_id, int index, fbv_prop* out);
  int quantity_count(std::int64_t element_id);
  int quantity_at(std::int64_t element_id, int index, fbv_quantity* out);
  int classification_count(std::int64_t element_id);
  int classification_at(std::int64_t element_id, int index, fbv_classification* out);
  int world_aabb(std::int64_t element_id, double min_xyz[3], double max_xyz[3]) const;
  int search(const char* query, std::int64_t* ids, int cap, int* total);
  int spec_count();
  int spec_at(int index, fbv_spec_row* out);

 private:
  int fill_element(fbv::Stmt& stmt, fbv_element_info* out);
  void set_error(const std::string& message) const { error = message; }
};

fbv_package* fbv_package_open_impl(const char* path, std::string& error);
