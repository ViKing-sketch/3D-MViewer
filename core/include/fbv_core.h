#ifndef FBV_CORE_H
#define FBV_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(FBV_CORE_SHARED)
#if defined(FBV_CORE_BUILD)
#define FBV_API __declspec(dllexport)
#else
#define FBV_API __declspec(dllimport)
#endif
#else
#define FBV_API
#endif

#define FBV_OK 0
#define FBV_ERR 1
#define FBV_ERR_RANGE 2

typedef struct fbv_package fbv_package;

typedef struct fbv_manifest_info {
  int32_t format_version;
  int32_t element_count;
  int32_t mesh_element_count;
  int32_t spatial_count;
  int32_t warning_count;
  double local_origin[3];
  double world_min[3];
  double world_max[3];
  char name[256];
  char source_file[256];
  char source_schema[32];
  char length_unit[32];
  char brep_codec[32];
} fbv_manifest_info;

typedef struct fbv_spatial_info {
  int64_t id;
  int64_t parent_id;
  double elevation;
  int32_t has_elevation;
  int32_t child_count;
  char kind[32];
  char name[256];
} fbv_spatial_info;

typedef struct fbv_element_info {
  int64_t id;
  int64_t storey_id;
  int64_t parent_id;
  int64_t type_id;
  int32_t mesh_node;
  int32_t has_brep;
  int32_t has_bbox;
  int32_t pad;
  double bbox_min[3];
  double bbox_max[3];
  float color[3];
  float color_pad;
  char guid[64];
  char ifc_class[64];
  char name[256];
  char tag[64];
  char type_name[128];
  char material[128];
} fbv_element_info;

typedef struct fbv_prop {
  char pset[128];
  char name[128];
  char value_text[512];
  char unit[32];
  char data_type[32];
  char source[16];
  double value_num;
  int32_t has_num;
  int32_t pad;
} fbv_prop;

typedef struct fbv_quantity {
  char qset[128];
  char name[128];
  char kind[32];
  char unit[32];
  double value;
} fbv_quantity;

typedef struct fbv_classification {
  char system_name[128];
  char code[128];
  char title[256];
} fbv_classification;

typedef struct fbv_spec_row {
  int64_t storey_id;
  int32_t element_count;
  int32_t has_quantity;
  double quantity_sum;
  char ifc_class[64];
  char type_name[128];
  char material_name[128];
  char quantity_kind[32];
  char storey_name[128];
} fbv_spec_row;

FBV_API const char* fbv_core_version(void);

FBV_API fbv_package* fbv_package_open(const char* path, char* err, size_t err_len);
FBV_API void fbv_package_close(fbv_package* package);
FBV_API const char* fbv_package_error(const fbv_package* package);

FBV_API int fbv_package_manifest(const fbv_package* package, fbv_manifest_info* out);

FBV_API int fbv_spatial_count(const fbv_package* package);
FBV_API int fbv_spatial_at(const fbv_package* package, int index, fbv_spatial_info* out);

FBV_API int fbv_element_count(const fbv_package* package);
FBV_API int fbv_element_at(const fbv_package* package, int index, fbv_element_info* out);
FBV_API int fbv_element_by_id(const fbv_package* package, int64_t id, fbv_element_info* out);

FBV_API int fbv_element_prop_count(const fbv_package* package, int64_t element_id);
FBV_API int fbv_element_prop_at(const fbv_package* package, int64_t element_id, int index,
                                fbv_prop* out);

FBV_API int fbv_element_quantity_count(const fbv_package* package, int64_t element_id);
FBV_API int fbv_element_quantity_at(const fbv_package* package, int64_t element_id, int index,
                                    fbv_quantity* out);

FBV_API int fbv_element_classification_count(const fbv_package* package, int64_t element_id);
FBV_API int fbv_element_classification_at(const fbv_package* package, int64_t element_id, int index,
                                          fbv_classification* out);

FBV_API int fbv_element_world_aabb(const fbv_package* package, int64_t element_id,
                                   double min_xyz[3], double max_xyz[3]);

/* ids receives up to cap matches. *total is the full match count. */
FBV_API int fbv_search(const fbv_package* package, const char* query, int64_t* ids, int cap,
                       int* total);

FBV_API int fbv_spec_count(const fbv_package* package);
FBV_API int fbv_spec_at(const fbv_package* package, int index, fbv_spec_row* out);

FBV_API int fbv_abi_manifest_size(void);
FBV_API int fbv_abi_spatial_size(void);
FBV_API int fbv_abi_element_size(void);
FBV_API int fbv_abi_prop_size(void);

#ifdef __cplusplus
}
#endif

#endif
