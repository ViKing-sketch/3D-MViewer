#include "fbv/convert.hpp"
#include "fbv/glb.hpp"
#include "fbv/io.hpp"
#include "fbv/sqlite_util.hpp"
#include "fbv_core.h"
#include "ifc_parse.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>
#if !defined(_WIN32)
#include <sys/wait.h>
#endif

#ifndef FBV_TESTDATA_DIR
#define FBV_TESTDATA_DIR "testdata"
#endif

namespace {

int g_failed = 0;

void check(bool condition, const char* text, int line) {
  if (!condition) {
    std::cerr << "FAIL " << line << ": " << text << "\n";
    ++g_failed;
  }
}

#define CHECK(cond) check(static_cast<bool>(cond), #cond, __LINE__)

bool near(double a, double b, double tol = 1e-4) {
  return std::abs(a - b) <= tol;
}

void bounds(const std::vector<float>& xyz, float out_min[3], float out_max[3]) {
  out_min[0] = out_max[0] = xyz[0];
  out_min[1] = out_max[1] = xyz[1];
  out_min[2] = out_max[2] = xyz[2];
  for (std::size_t i = 0; i + 2 < xyz.size(); i += 3) {
    for (int axis = 0; axis < 3; ++axis) {
      out_min[axis] = std::min(out_min[axis], xyz[i + static_cast<std::size_t>(axis)]);
      out_max[axis] = std::max(out_max[axis], xyz[i + static_cast<std::size_t>(axis)]);
    }
  }
}

fbv_prop find_prop(fbv_package* package, std::int64_t id, const std::string& name) {
  const int count = fbv_element_prop_count(package, id);
  for (int i = 0; i < count; ++i) {
    fbv_prop prop{};
    if (fbv_element_prop_at(package, id, i, &prop) == FBV_OK && prop.name == name) return prop;
  }
  return {};
}

int run_cli(const std::string& command) {
#if defined(_WIN32)
  // cmd.exe /c drops the first and last quote when the line starts with `"`.
  const std::string wrapped = "\"" + command + "\"";
  const int rc = std::system(wrapped.c_str());
#else
  const int rc = std::system(command.c_str());
#endif
  if (rc == -1) return -1;
#if defined(_WIN32)
  return rc;
#else
  if (WIFEXITED(rc)) return WEXITSTATUS(rc);
  return -1;
#endif
}

}  // namespace

int main() {
  CHECK(fbv::decode_ifc_string("\\X2\\041C04300440043A0430\\X0\\") == "Марка");
  CHECK(fbv::decode_ifc_string("\\X2\\041D0421002D00310032\\X0\\") == "НС-12");
  {
    const auto quoted = fbv::parse_ifc(
        "ISO-10303-21;HEADER;FILE_SCHEMA(('IFC4'));ENDSEC;DATA;"
        "#1=IFCPROPERTYSINGLEVALUE('A''B',$,$,$);ENDSEC;END-ISO-10303-21;");
    CHECK(quoted.find(1) != nullptr);
    CHECK(quoted.find(1)->attrs[0].text == "A'B");
  }

  const std::filesystem::path testdata = FBV_TESTDATA_DIR;
  const auto root = std::filesystem::temp_directory_path() / "fbv-converter-tests";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root);
  const auto directory = root / "sample_model";
  fbv::ConvertOptions options;
  options.output = directory.string();
  options.as_directory = true;
  const auto status = fbv::convert_file((testdata / "sample_wall.ifc").string(), options);
  if (status.code != 0) std::cerr << status.error << "\n";
  CHECK(status.code == 0);
  CHECK(status.elements == 4);
  CHECK(status.with_mesh == 3);
  CHECK(status.warnings >= 1);

  char err[512] = {};
  fbv_package* package = fbv_package_open(directory.string().c_str(), err, sizeof(err));
  if (package == nullptr) std::cerr << err << "\n";
  CHECK(package != nullptr);
  if (package != nullptr) {
    fbv_manifest_info info{};
    CHECK(fbv_package_manifest(package, &info) == FBV_OK);
    CHECK(info.format_version == 1);
    CHECK(std::string(info.name) == "Sample Project");
    CHECK(std::string(info.source_schema) == "IFC4");
    CHECK(std::string(info.length_unit) == "millimetre");
    CHECK(std::string(info.brep_codec) == "analytic-box-v1");
    CHECK(info.element_count == 4);
    CHECK(info.mesh_element_count == 3);
    const double site_x = 10000000.0 * 0.001;
    const double site_y = 20000000.0 * 0.001;
    CHECK(near(info.local_origin[0], site_x - 3.0));
    CHECK(near(info.local_origin[1], site_y - 2.0));
    CHECK(near(info.local_origin[2], -0.2));

    CHECK(fbv_spatial_count(package) == 4);
    fbv_spatial_info project{};
    CHECK(fbv_spatial_at(package, 0, &project) == FBV_OK);
    CHECK(std::string(project.kind) == "Project");
    CHECK(std::string(project.name) == "Sample Project");
    CHECK(project.parent_id == 0);
    fbv_spatial_info storey{};
    CHECK(fbv_spatial_at(package, 3, &storey) == FBV_OK);
    CHECK(std::string(storey.kind) == "Storey");
    CHECK(std::string(storey.name) == "Level 1");
    CHECK(storey.has_elevation == 1);
    CHECK(near(storey.elevation, 0));
    CHECK(storey.parent_id != 0);

    CHECK(fbv_element_count(package) == 4);
    fbv_element_info wall{};
    CHECK(fbv_element_by_id(package, 1, &wall) == FBV_OK);
    CHECK(std::string(wall.ifc_class) == "IfcWall");
    CHECK(std::string(wall.name) == "Wall W-1");
    CHECK(std::string(wall.tag) == "W-1");
    CHECK(std::string(wall.type_name) == "Basic Wall 200");
    CHECK(std::string(wall.material) == "Бетон");
    CHECK(wall.mesh_node >= 0);
    CHECK(wall.has_brep == 1);
    CHECK(wall.has_bbox == 1);
    CHECK(wall.storey_id == storey.id);
    CHECK(near(wall.bbox_min[0], site_x - 2.5));
    CHECK(near(wall.bbox_min[1], site_y - 0.1));
    CHECK(near(wall.bbox_min[2], 0));
    CHECK(near(wall.bbox_max[0], site_x + 2.5));
    CHECK(near(wall.bbox_max[2], 3));

    double amin[3] = {};
    double amax[3] = {};
    CHECK(fbv_element_world_aabb(package, 1, amin, amax) == FBV_OK);
    CHECK(near(amin[0], wall.bbox_min[0]));
    CHECK(near(amax[2], wall.bbox_max[2]));

    const fbv_prop reference = find_prop(package, 1, "Reference");
    CHECK(std::string(reference.value_text) == "W-1");
    const fbv_prop external = find_prop(package, 1, "IsExternal");
    CHECK(std::string(external.value_text) == "true");
    const fbv_prop mark = find_prop(package, 1, "Марка");
    CHECK(std::string(mark.value_text) == "НС-12");

    CHECK(fbv_element_quantity_count(package, 1) == 4);
    bool saw_length = false;
    bool saw_volume = false;
    for (int i = 0; i < 4; ++i) {
      fbv_quantity quantity{};
      CHECK(fbv_element_quantity_at(package, 1, i, &quantity) == FBV_OK);
      if (std::string(quantity.name) == "Length") {
        saw_length = true;
        CHECK(near(quantity.value, 5.0));
        CHECK(std::string(quantity.unit) == "m");
      }
      if (std::string(quantity.name) == "GrossVolume") {
        saw_volume = true;
        CHECK(near(quantity.value, 3.0));
      }
    }
    CHECK(saw_length && saw_volume);
    CHECK(fbv_element_classification_count(package, 1) == 1);
    fbv_classification classification{};
    CHECK(fbv_element_classification_at(package, 1, 0, &classification) == FBV_OK);
    CHECK(std::string(classification.system_name) == "КСИ");
    CHECK(std::string(classification.code) == "C1");
    CHECK(std::string(classification.title) == "Walls");

    fbv_element_info proxy{};
    CHECK(fbv_element_by_id(package, 4, &proxy) == FBV_OK);
    CHECK(std::string(proxy.ifc_class) == "IfcBuildingElementProxy");
    CHECK(proxy.mesh_node < 0);
    CHECK(proxy.has_brep == 0);

    int total = 0;
    std::int64_t ids[8] = {};
    CHECK(fbv_search(package, "НС-12", ids, 8, &total) == FBV_OK);
    CHECK(total >= 1);
    CHECK(ids[0] == 1);
    CHECK(fbv_search(package, "Column", ids, 8, &total) == FBV_OK);
    CHECK(total >= 1);
    bool found_column = false;
    for (int i = 0; i < total && i < 8; ++i) {
      if (ids[i] == 2) found_column = true;
    }
    CHECK(found_column);
    CHECK(fbv_spec_count(package) >= 4);

    fbv::GlbContents wall_glb;
    std::string glb_error;
    CHECK(fbv::read_glb(directory / "mesh" / "elements" / "1.glb", wall_glb, glb_error));
    std::vector<float> xyz;
    CHECK(fbv::glb_positions(wall_glb, xyz, glb_error));
    CHECK(xyz.size() == 36 * 3);  // 12 triangles, unshared vertices
    float gmin[3] = {};
    float gmax[3] = {};
    bounds(xyz, gmin, gmax);
    CHECK(near(gmin[0], (site_x - 2.5) - info.local_origin[0], 1e-3));
    CHECK(near(gmin[1], (site_y - 0.1) - info.local_origin[1], 1e-3));
    CHECK(near(gmin[2], 0.0 - info.local_origin[2], 1e-3));
    CHECK(near(gmax[0], (site_x + 2.5) - info.local_origin[0], 1e-3));
    CHECK(near(gmax[2], 3.0 - info.local_origin[2], 1e-3));

    fbv::SqliteDb db(directory / "meta.sqlite", false);
    auto thickness = db.prepare(
        "SELECT ml.thickness FROM material_layers ml JOIN elements e ON e.material_set_id = "
        "ml.set_id "
        "WHERE e.id = 1");
    CHECK(thickness.step_row());
    CHECK(near(thickness.column_double(0), 0.2));
    fbv_package_close(package);
  }

  std::string report;
  CHECK(fbv::validate_package(directory.string(), report) == 0);

  const auto zip_path = root / "sample.fbvpkg";
  fbv::ConvertOptions zip_options = options;
  zip_options.output = zip_path.string();
  zip_options.as_directory = false;
  const auto zipped = fbv::convert_file((testdata / "sample_wall.ifc").string(), zip_options);
  CHECK(zipped.code == 0);
  CHECK(fbv::validate_package(zip_path.string(), report) == 0);
  fbv_package* zipped_pkg = fbv_package_open(zip_path.string().c_str(), err, sizeof(err));
  CHECK(zipped_pkg != nullptr);
  if (zipped_pkg != nullptr) {
    CHECK(fbv_element_count(zipped_pkg) == 4);
    fbv_package_close(zipped_pkg);
  }

  auto tampered = root / "tampered";
  std::filesystem::remove_all(tampered);
  if (std::filesystem::exists(directory)) {
    std::filesystem::copy(directory, tampered, std::filesystem::copy_options::recursive);
    {
      const auto glb = tampered / "mesh" / "lod0.glb";
      auto bytes = fbv::read_text(glb.string());
      if (!bytes.empty())
        bytes[bytes.size() / 2] = static_cast<char>(bytes[bytes.size() / 2] ^ 0x5A);
      fbv::write_text(glb, bytes);
    }
    CHECK(fbv::validate_package(tampered.string(), report) == 3);
    fbv_package* bad = fbv_package_open(tampered.string().c_str(), err, sizeof(err));
    CHECK(bad == nullptr);
  }

  fbv::ConvertOptions columns = options;
  columns.output = (root / "columns").string();
  columns.class_filter = {"IfcColumn"};
  const auto only_columns = fbv::convert_file((testdata / "sample_wall.ifc").string(), columns);
  CHECK(only_columns.code == 0);
  CHECK(only_columns.elements == 1);
  CHECK(only_columns.with_mesh == 1);

  fbv::ConvertOptions no_brep = options;
  no_brep.output = (root / "no_brep").string();
  no_brep.write_brep = false;
  const auto without_brep = fbv::convert_file((testdata / "sample_wall.ifc").string(), no_brep);
  CHECK(without_brep.code == 0);
  CHECK(fbv::validate_package(no_brep.output, report) == 0);
  CHECK(!std::filesystem::exists(std::filesystem::path(no_brep.output) / "brep.pack"));

  const char* prism = R"(ISO-10303-21;
HEADER;
FILE_SCHEMA(('IFC2X3'));
ENDSEC;
DATA;
#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);
#2=IFCCARTESIANPOINT((0.,0.));
#3=IFCCARTESIANPOINT((1.,0.));
#4=IFCCARTESIANPOINT((0.,1.));
#5=IFCPOLYLINE((#2,#3,#4,#2));
#6=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,#5);
#7=IFCDIRECTION((0.,0.,1.));
#8=IFCDIRECTION((1.,0.,0.));
#9=IFCCARTESIANPOINT((0.,0.,0.));
#10=IFCAXIS2PLACEMENT3D(#9,#7,#8);
#11=IFCEXTRUDEDAREASOLID(#6,#10,#7,1.);
#12=IFCSHAPEREPRESENTATION($,'Body','SweptSolid',(#11));
#13=IFCPRODUCTDEFINITIONSHAPE($,$,(#12));
#14=IFCWALL('0Yvh4$d$H4PgX8k1$f$x99',$,'Tri',$,$,$,#13,$,$);
ENDSEC;
END-ISO-10303-21;
)";
  fbv::ConvertOptions prism_options;
  prism_options.output = (root / "prism").string();
  prism_options.as_directory = true;
  prism_options.source_name = "prism.ifc";
  const auto prism_status = fbv::convert_text(prism, prism_options);
  if (prism_status.code != 0) std::cerr << prism_status.error << "\n";
  CHECK(prism_status.code == 0);
  CHECK(prism_status.elements == 1);
  CHECK(prism_status.with_mesh == 1);
  fbv::GlbContents prism_glb;
  std::string prism_error;
  CHECK(fbv::read_glb(std::filesystem::path(prism_options.output) / "mesh" / "elements" / "1.glb",
                      prism_glb, prism_error));
  std::vector<float> prism_xyz;
  CHECK(fbv::glb_positions(prism_glb, prism_xyz, prism_error));
  CHECK(prism_xyz.size() == 24 * 3);
  float pmin[3] = {};
  float pmax[3] = {};
  bounds(prism_xyz, pmin, pmax);
  CHECK(near(pmin[0], 0, 1e-4) && near(pmin[1], 0, 1e-4) && near(pmin[2], 0, 1e-4));
  CHECK(near(pmax[0], 1, 1e-4) && near(pmax[1], 1, 1e-4) && near(pmax[2], 1, 1e-4));

  fbv::ConvertOptions step_options;
  step_options.output = (root / "step.fbvpkg").string();
  const auto step = fbv::convert_file((testdata / "not_ifc.step").string(), step_options);
  CHECK(step.code == 2);
  CHECK(step.error.find("OCCT") != std::string::npos);

  const char* fbvconv = std::getenv("FBV_FBVCONV");
  const char* validator = std::getenv("FBV_PKG_VALIDATE");
  if (fbvconv != nullptr && validator != nullptr) {
    const auto cli_out = root / "cli.fbvpkg";
    const std::string cmd = std::string("\"") + fbvconv + "\" \"" +
                            (testdata / "sample_wall.ifc").string() + "\" -o \"" +
                            cli_out.string() + "\"";
    const int cli_rc = run_cli(cmd);
    if (cli_rc != 0) std::cerr << "cli exit " << cli_rc << ": " << cmd << "\n";
    CHECK(cli_rc == 0);
    const std::string validate_cmd =
        std::string("\"") + validator + "\" \"" + cli_out.string() + "\"";
    const int validate_rc = run_cli(validate_cmd);
    if (validate_rc != 0)
      std::cerr << "validate exit " << validate_rc << ": " << validate_cmd << "\n";
    CHECK(validate_rc == 0);
  }

  if (g_failed != 0) {
    std::cerr << g_failed << " converter checks failed\n";
    return 1;
  }
  std::cout << "converter_tests ok\n";
  return 0;
}
