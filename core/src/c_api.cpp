#include "package.hpp"

#include "fbv_version.h"

#include <cstdio>
#include <cstring>

namespace {

void write_err(char* err, size_t err_len, const std::string& message) {
  if (err == nullptr || err_len == 0) return;
  std::snprintf(err, err_len, "%s", message.c_str());
}

fbv_package* as_pkg(const fbv_package* package) {
  return const_cast<fbv_package*>(package);
}

}  // namespace

const char* fbv_core_version(void) {
  return FBV_VERSION_STRING;
}

fbv_package* fbv_package_open(const char* path, char* err, size_t err_len) {
  std::string message;
  fbv_package* package = nullptr;
  try {
    package = fbv_package_open_impl(path, message);
  } catch (const std::exception& ex) {
    message = ex.what();
    package = nullptr;
  }
  if (package == nullptr) write_err(err, err_len, message);
  return package;
}

void fbv_package_close(fbv_package* package) {
  delete package;
}

const char* fbv_package_error(const fbv_package* package) {
  if (package == nullptr) return "null package";
  return package->error.c_str();
}

int fbv_package_manifest(const fbv_package* package, fbv_manifest_info* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return package->manifest_info(out);
}

int fbv_spatial_count(const fbv_package* package) {
  if (package == nullptr) return -1;
  return as_pkg(package)->spatial_count();
}

int fbv_spatial_at(const fbv_package* package, int index, fbv_spatial_info* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->spatial_at(index, out);
}

int fbv_element_count(const fbv_package* package) {
  if (package == nullptr) return -1;
  return as_pkg(package)->element_count();
}

int fbv_element_at(const fbv_package* package, int index, fbv_element_info* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->element_at(index, out);
}

int fbv_element_by_id(const fbv_package* package, int64_t id, fbv_element_info* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->element_by_id(id, out);
}

int fbv_element_prop_count(const fbv_package* package, int64_t element_id) {
  if (package == nullptr) return -1;
  return as_pkg(package)->prop_count(element_id);
}

int fbv_element_prop_at(const fbv_package* package, int64_t element_id, int index, fbv_prop* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->prop_at(element_id, index, out);
}

int fbv_element_quantity_count(const fbv_package* package, int64_t element_id) {
  if (package == nullptr) return -1;
  return as_pkg(package)->quantity_count(element_id);
}

int fbv_element_quantity_at(const fbv_package* package, int64_t element_id, int index,
                            fbv_quantity* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->quantity_at(element_id, index, out);
}

int fbv_element_classification_count(const fbv_package* package, int64_t element_id) {
  if (package == nullptr) return -1;
  return as_pkg(package)->classification_count(element_id);
}

int fbv_element_classification_at(const fbv_package* package, int64_t element_id, int index,
                                  fbv_classification* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->classification_at(element_id, index, out);
}

int fbv_element_world_aabb(const fbv_package* package, int64_t element_id, double min_xyz[3],
                           double max_xyz[3]) {
  if (package == nullptr || min_xyz == nullptr || max_xyz == nullptr) return FBV_ERR;
  return package->world_aabb(element_id, min_xyz, max_xyz);
}

int fbv_search(const fbv_package* package, const char* query, int64_t* ids, int cap, int* total) {
  if (package == nullptr) return FBV_ERR;
  return as_pkg(package)->search(query, ids, cap, total);
}

int fbv_spec_count(const fbv_package* package) {
  if (package == nullptr) return -1;
  return as_pkg(package)->spec_count();
}

int fbv_spec_at(const fbv_package* package, int index, fbv_spec_row* out) {
  if (package == nullptr || out == nullptr) return FBV_ERR;
  return as_pkg(package)->spec_at(index, out);
}

int fbv_abi_manifest_size(void) {
  return static_cast<int>(sizeof(fbv_manifest_info));
}
int fbv_abi_spatial_size(void) {
  return static_cast<int>(sizeof(fbv_spatial_info));
}
int fbv_abi_element_size(void) {
  return static_cast<int>(sizeof(fbv_element_info));
}
int fbv_abi_prop_size(void) {
  return static_cast<int>(sizeof(fbv_prop));
}
