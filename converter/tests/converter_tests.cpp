#include "discipline.hpp"
#include "fbv/convert.hpp"
#include "fbv/glb.hpp"
#include "fbv/io.hpp"
#include "fbv/sha256.hpp"
#include "fbv/sqlite_util.hpp"
#include "fbv_core.h"
#include "ifc_parse.hpp"
#include "mesh_stream.hpp"
#include "scene.hpp"
#include "write_pkg.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>
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
  CHECK(fbv::assign_discipline("IfcWall", {}) == "architecture");
  CHECK(fbv::assign_discipline("IfcDuctSegment", {}) == "ventilation");
  CHECK(fbv::assign_discipline("IfcBuildingElementProxy", {}) == "");
  CHECK(fbv::assign_discipline("IfcWall", {"Heating water"}) == "heating");
  CHECK(fbv::assign_discipline("IfcBuildingElementProxy", {"Вентиляция стояка"}) == "ventilation");
  CHECK(fbv::assign_discipline("IfcWall", {"Structure frame", "Heating"}) == "structure");
  CHECK(fbv::decode_ifc_string("\\X2\\041C04300440043A0430\\X0\\") == "Марка");
  CHECK(fbv::decode_ifc_string("\\X2\\041D0421002D00310032\\X0\\") == "НС-12");
  CHECK(fbv::decode_ifc_string("\\S\\ ") == "\xC2\xA0");
  CHECK(fbv::decode_ifc_string("\\X\\A0") == "\xC2\xA0");
  {
    std::string raw(53, 'A');
    raw.push_back(static_cast<char>(0xA0));
    const auto text = fbv::decode_ifc_string(raw);
    CHECK(text.size() == 55);
    CHECK(text.compare(0, 53, std::string(53, 'A')) == 0);
    CHECK(static_cast<unsigned char>(text[53]) == 0xC2);
    CHECK(static_cast<unsigned char>(text[54]) == 0xA0);
  }
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
  CHECK(status.failed == 0);
  CHECK(status.warnings >= 1);
  CHECK(status.completeness_ok);

  char err[512] = {};
  fbv_package* package = fbv_package_open(directory.string().c_str(), err, sizeof(err));
  if (package == nullptr) std::cerr << err << "\n";
  CHECK(package != nullptr);
  if (package != nullptr) {
    fbv_manifest_info info{};
    CHECK(fbv_package_manifest(package, &info) == FBV_OK);
    CHECK(info.format_version == 4);
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
    const std::string manifest_text = fbv::read_text((directory / "manifest.json").string());
    const bool ios_mesh = manifest_text.find("ifcopenshell-occt") != std::string::npos;
    if (!ios_mesh)
      CHECK(xyz.size() == 36 * 3);  // 12 triangles, unshared vertices
    else
      CHECK(xyz.size() >= 8 * 3);
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
    auto tile_rows = db.prepare("SELECT COUNT(*) FROM tile_elements");
    CHECK(tile_rows.step_row());
    CHECK(tile_rows.column_int64(0) == 4);
    auto dup = db.prepare(
        "SELECT COUNT(*) FROM (SELECT element_id FROM tile_elements GROUP BY element_id HAVING "
        "COUNT(*) > 1)");
    CHECK(dup.step_row());
    CHECK(dup.column_int64(0) == 0);
    auto wall_tile = db.prepare(
        "SELECT t.discipline, t.storey_id FROM tiles t JOIN tile_elements te ON te.tile_id = t.id "
        "WHERE te.element_id = 1");
    CHECK(wall_tile.step_row());
    CHECK(std::string(wall_tile.column_text(0)) == "architecture");
    CHECK(wall_tile.column_int64(1) == storey.id);
    auto proxy_tile = db.prepare(
        "SELECT t.discipline FROM tiles t JOIN tile_elements te ON te.tile_id = t.id "
        "JOIN elements e ON e.id = te.element_id WHERE e.ifc_class = 'IfcBuildingElementProxy'");
    CHECK(proxy_tile.step_row());
    CHECK(std::string(proxy_tile.column_text(0)).empty());
    auto exact =
        db.prepare("SELECT element_id, path, bytes FROM exact_geometry ORDER BY element_id");
    int exact_rows = 0;
    while (exact.step_row()) {
      ++exact_rows;
      const auto id = exact.column_int64(0);
      const std::string path = exact.column_text(1);
      const auto nbytes = exact.column_int64(2);
      CHECK(path == "geometry/elements/" + std::to_string(id) + ".brep");
      CHECK(nbytes > 0);
      const auto file = directory / std::filesystem::path(path);
      CHECK(std::filesystem::is_regular_file(file));
      CHECK(static_cast<std::int64_t>(std::filesystem::file_size(file)) == nbytes);
    }
    if (ios_mesh)
      CHECK(exact_rows > 0);
    else
      CHECK(exact_rows == 0);
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
  {
    const std::string prism_manifest =
        fbv::read_text((std::filesystem::path(prism_options.output) / "manifest.json").string());
    const bool ios_mesh = prism_manifest.find("ifcopenshell-occt") != std::string::npos;
    if (!ios_mesh)
      CHECK(prism_xyz.size() == 24 * 3);
    else
      CHECK(prism_xyz.size() >= 4 * 3);
  }
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
    const auto cli_json = root / "cli.json";
    const std::string cmd = std::string("\"") + fbvconv + "\" \"" +
                            (testdata / "sample_wall.ifc").string() + "\" -o \"" +
                            cli_out.string() + "\" --stats --json \"" + cli_json.string() +
                            "\" --max-threads 2 --max-memory 64";
    const int cli_rc = run_cli(cmd);
    if (cli_rc != 0) std::cerr << "cli exit " << cli_rc << ": " << cmd << "\n";
    CHECK(cli_rc == 0);
    CHECK(std::filesystem::is_regular_file(cli_json));
    if (std::filesystem::is_regular_file(cli_json)) {
      const std::string summary = fbv::read_text(cli_json.string());
      CHECK(summary.find("\"with_mesh\"") != std::string::npos);
      CHECK(summary.find("\"peak_rss_bytes\"") != std::string::npos);
      CHECK(summary.find("\"mesh_bytes_peak\"") != std::string::npos);
      CHECK(summary.find("\"warning_reasons\"") != std::string::npos);
      CHECK(summary.find("\"no_representation\"") != std::string::npos);
      CHECK(summary.find("\"max_threads\": 2") != std::string::npos);
      CHECK(summary.find("\"max_memory_mb\": 64") != std::string::npos);
      CHECK(summary.find("\"timings_s\"") != std::string::npos);
      CHECK(summary.find("\"completeness\": \"ok\"") != std::string::npos);
    }
    const std::string validate_cmd =
        std::string("\"") + validator + "\" \"" + cli_out.string() + "\"";
    const int validate_rc = run_cli(validate_cmd);
    if (validate_rc != 0)
      std::cerr << "validate exit " << validate_rc << ": " << validate_cmd << "\n";
    CHECK(validate_rc == 0);
  }

  {
    fbv::ConvertOptions poly_options;
    poly_options.output = (root / "polyline").string();
    poly_options.as_directory = true;
    const auto poly = fbv::convert_file((testdata / "polyline_ifc2x3.ifc").string(), poly_options);
    if (poly.code != 0) std::cerr << poly.error << "\n";
    CHECK(poly.code == 0);
    CHECK(poly.elements == 1);
    CHECK(poly.with_mesh == 1);
    CHECK(poly.failed == 0);
  }

  auto expect_solid = [&](const char* filename, const char* label, double min_x, double max_x) {
    fbv::ConvertOptions solid_options;
    solid_options.output = (root / label).string();
    solid_options.as_directory = true;
    solid_options.source_name = filename;
    const auto solid = fbv::convert_file((testdata / filename).string(), solid_options);
    if (solid.code != 0) std::cerr << solid.error << "\n";
    CHECK(solid.code == 0);
    CHECK(solid.elements == 1);
    CHECK(solid.completeness_ok);
    const std::string manifest =
        fbv::read_text((std::filesystem::path(solid_options.output) / "manifest.json").string());
    const bool ios_mesh = manifest.find("ifcopenshell-occt") != std::string::npos;
    if (ios_mesh) {
      CHECK(solid.with_mesh == 1);
      CHECK(solid.failed == 0);
      char open_err[512] = {};
      fbv_package* solid_pkg =
          fbv_package_open(solid_options.output.c_str(), open_err, sizeof(open_err));
      CHECK(solid_pkg != nullptr);
      if (solid_pkg != nullptr) {
        fbv_element_info solid_info{};
        CHECK(fbv_element_by_id(solid_pkg, 1, &solid_info) == FBV_OK);
        CHECK(solid_info.mesh_node >= 0);
        CHECK(near(solid_info.bbox_min[0], min_x, 1e-3));
        CHECK(near(solid_info.bbox_max[0], max_x, 1e-3));
        CHECK(near(solid_info.bbox_min[1], 0, 1e-3) && near(solid_info.bbox_min[2], 0, 1e-3));
        CHECK(near(solid_info.bbox_max[1], 1, 1e-3) && near(solid_info.bbox_max[2], 1, 1e-3));
        fbv_package_close(solid_pkg);
      }
    } else {
      CHECK(solid.with_mesh == 0);
      CHECK(solid.failed == 1);
    }
    std::string solid_report;
    CHECK(fbv::validate_package(solid_options.output, solid_report) == 0);
  };
  expect_solid("brep_box.ifc", "brep_box", 0, 1);
  expect_solid("mapped_box.ifc", "mapped_box", 2, 3);

  {
    // Synthetic stand-in for a large model: several meshes bigger than the RAM budget.
    // Private IFC files are not in the repo. This checks that they are spilled and that
    // the package still contains every vertex.
    fbv::Scene scene;
    scene.schema = "IFC4";
    scene.project_name = "Streamed";
    scene.has_world = true;
    scene.origin = {5, 5, 5};
    fbv::ConvertOptions stream_options;
    stream_options.output = (root / "streamed").string();
    stream_options.as_directory = true;
    stream_options.write_brep = false;
    stream_options.source_name = "streamed.ifc";
    stream_options.max_memory_mb = 1;
    constexpr int kElements = 4;
    constexpr int kDoubles = 90000;
    for (int i = 0; i < kElements; ++i) {
      fbv::Element element;
      element.id = i + 1;
      element.guid = "STREAM" + std::to_string(i);
      element.ifc_class = "IfcWall";
      element.name = "S" + std::to_string(i);
      element.has_mesh = true;
      element.has_representation = true;
      element.mesh.position.assign(kDoubles, 5.0);
      element.mesh.normal.assign(kDoubles, 0.0);
      element.mesh.indices = {0, 1, 2};
      fbv::commit_mesh(scene, element, stream_options);
      scene.elements.push_back(std::move(element));
    }
    CHECK(scene.mesh_resident_bytes == 0);
    CHECK(scene.mesh_bytes_peak > 1024ull * 1024ull);
    CHECK(scene.mesh_bytes_peak < 3ull * 1024ull * 1024ull);
    for (const fbv::Element& element : scene.elements) {
      CHECK(element.mesh.position.empty());
      CHECK(!element.mesh_scratch.empty());
      CHECK(element.triangle_count == 1);
    }
    fbv::write_scene_package(scene, stream_options, "ISO-10303-21;", "streamed.ifc");
    std::string stream_report;
    CHECK(fbv::validate_package(stream_options.output, stream_report) == 0);
    fbv::GlbContents streamed_glb;
    std::string streamed_error;
    CHECK(
        fbv::read_glb(std::filesystem::path(stream_options.output) / "mesh" / "elements" / "1.glb",
                      streamed_glb, streamed_error));
    std::vector<float> streamed_xyz;
    CHECK(fbv::glb_positions(streamed_glb, streamed_xyz, streamed_error));
    CHECK(streamed_xyz.size() == static_cast<std::size_t>(kDoubles));
    CHECK(near(streamed_xyz.front(), 0.0, 1e-4));
    CHECK(near(streamed_xyz.back(), 0.0, 1e-4));
  }

  {
    // A second representation reloads a spilled mesh. If the combined mesh fits
    // in the budget, the old scratch file must not stay behind as the source.
    fbv::Scene scene;
    fbv::Element element;
    element.id = 7;
    element.has_mesh = true;
    fbv::ConvertOptions tight;
    tight.max_memory_mb = 1;
    element.mesh.position.assign(90000, 1.0);
    element.mesh.normal.assign(90000, 0.0);
    element.mesh.indices = {0, 1, 2};
    fbv::commit_mesh(scene, element, tight);
    CHECK(element.mesh.position.empty());
    CHECK(!element.mesh_scratch.empty());
    fbv::reload_mesh_world(scene, element);
    element.mesh.position.insert(element.mesh.position.end(), {8.0, 8.0, 8.0});
    element.mesh.normal.insert(element.mesh.normal.end(), {0.0, 0.0, 1.0});
    element.mesh.indices.insert(element.mesh.indices.end(), {1, 2, 3});
    fbv::ConvertOptions roomy;
    roomy.max_memory_mb = 64;
    fbv::commit_mesh(scene, element, roomy);
    CHECK(element.mesh_scratch.empty());
    CHECK(element.mesh.position.size() == 90003);
    CHECK(element.triangle_count == 2);
    CHECK(near(element.mesh.position.back(), 8.0, 1e-9));
    fbv::clear_mesh_scratch(scene);
  }

  {
    constexpr int kWalls = 24;
    std::ostringstream ifc;
    ifc << "ISO-10303-21;\nHEADER;\nFILE_SCHEMA(('IFC2X3'));\nENDSEC;\nDATA;\n";
    ifc << "#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n";
    ifc << "#2=IFCDIRECTION((0.,0.,1.));\n";
    ifc << "#3=IFCDIRECTION((1.,0.,0.));\n";
    ifc << "#4=IFCCARTESIANPOINT((0.,0.,0.));\n";
    ifc << "#5=IFCAXIS2PLACEMENT3D(#4,#2,#3);\n";
    const char* alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$";
    for (int i = 0; i < kWalls; ++i) {
      std::string guid = "0Yvh4$d$H4PgX8k1$f$x00";
      guid[20] = alphabet[(i / 64) % 64];
      guid[21] = alphabet[i % 64];
      const int base = 10 + i * 10;
      const double x = static_cast<double>(i) * 2.0;
      ifc << "#" << base << "=IFCCARTESIANPOINT((" << x << ",0.));\n";
      ifc << "#" << (base + 1) << "=IFCCARTESIANPOINT((" << (x + 1.0) << ",0.));\n";
      ifc << "#" << (base + 2) << "=IFCCARTESIANPOINT((" << x << ",1.));\n";
      ifc << "#" << (base + 3) << "=IFCPOLYLINE((#" << base << ",#" << (base + 1) << ",#"
          << (base + 2) << ",#" << base << "));\n";
      ifc << "#" << (base + 4) << "=IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,#" << (base + 3) << ");\n";
      ifc << "#" << (base + 5) << "=IFCEXTRUDEDAREASOLID(#" << (base + 4) << ",#5,#2,1.);\n";
      ifc << "#" << (base + 6) << "=IFCSHAPEREPRESENTATION($,'Body','SweptSolid',(#" << (base + 5)
          << "));\n";
      ifc << "#" << (base + 7) << "=IFCPRODUCTDEFINITIONSHAPE($,$,(#" << (base + 6) << "));\n";
      ifc << "#" << (base + 8) << "=IFCWALL('" << guid << "',$,'W" << i << "',$,$,$,#" << (base + 7)
          << ",$,$);\n";
    }
    ifc << "ENDSEC;\nEND-ISO-10303-21;\n";
    fbv::ConvertOptions many;
    many.output = (root / "many").string();
    many.as_directory = true;
    many.source_name = "many.ifc";
    many.max_threads = 2;
    many.max_memory_mb = 1;
    many.stats = true;
    many.json_output = (root / "many.json").string();
    const auto many_status = fbv::convert_text(ifc.str(), many);
    if (many_status.code != 0) std::cerr << many_status.error << "\n";
    CHECK(many_status.code == 0);
    CHECK(many_status.elements == kWalls);
    CHECK(many_status.with_mesh == kWalls);
    CHECK(many_status.failed == 0);
    CHECK(many_status.completeness_ok);
    CHECK(many_status.peak_rss_bytes > 0);
    CHECK(many_status.mesh_bytes_peak > 0);
    CHECK(many_status.mesh_bytes_peak < 8ull * 1024ull * 1024ull);
#ifdef FBV_WITH_IFCOPENSHELL
    CHECK(many_status.threads <= 2);
    CHECK(many_status.threads >= 2);
#endif
    const std::string many_json = fbv::read_text(many.json_output);
    CHECK(many_json.find("\"peak_rss_bytes\"") != std::string::npos);
    CHECK(many_json.find("\"warning_reasons\"") != std::string::npos);
    CHECK(many_json.find("\"max_threads\": 2") != std::string::npos);
    CHECK(many_json.find("\"mesh_budget_bytes\"") != std::string::npos);
    std::string many_report;
    CHECK(fbv::validate_package(many.output, many_report) == 0);
  }

  {
    char legacy_err[512] = {};
    fbv_package* legacy = fbv_package_open((testdata / "sample_model").string().c_str(), legacy_err,
                                           sizeof(legacy_err));
    if (legacy == nullptr) std::cerr << legacy_err << "\n";
    CHECK(legacy != nullptr);
    if (legacy != nullptr) {
      fbv_manifest_info legacy_info{};
      CHECK(fbv_package_manifest(legacy, &legacy_info) == FBV_OK);
      CHECK(legacy_info.format_version == 1);
      fbv_package_close(legacy);
    }
    std::string legacy_report;
    CHECK(fbv::validate_package((testdata / "sample_model").string(), legacy_report) == 0);

    std::ostringstream ifc;
    ifc << "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('ViewDefinition "
           "[CoordinationView]'),'2;1');\n";
    ifc << "FILE_NAME('systems.ifc','2026-11-08T00:00:00',(''),(''),'fbv','fbv','');\n";
    ifc << "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    ifc << "#1=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n";
    ifc << "#2=IFCUNITASSIGNMENT((#1));\n";
    ifc << "#3=IFCPROJECT('0Yvh4$d$H4PgX8k1$f$x00',$,'Systems',$,$,$,$,(),#2);\n";
    ifc << "#4=IFCWALL('0Yvh4$d$H4PgX8k1$f$x01',$,'Wall in system',$,$,$,$,'W-S',$);\n";
    ifc << "#5=IFCCOLUMN('0Yvh4$d$H4PgX8k1$f$x02',$,'Column out',$,$,$,$,'C-S',$);\n";
    ifc << "#6=IFCDISTRIBUTIONSYSTEM('0Yvh4$d$H4PgX8k1$f$x03',$,'Heating',$,$,$,.HEATING.);\n";
    ifc << "#7=IFCSYSTEM('0Yvh4$d$H4PgX8k1$f$x05',$,'Structure',$,$);\n";
    ifc << "#8=IFCRELASSIGNSTOGROUP('0Yvh4$d$H4PgX8k1$f$x04',$,$,$,(#4),$,#6);\n";
    ifc << "#9=IFCRELASSIGNSTOGROUP('0Yvh4$d$H4PgX8k1$f$x06',$,$,$,(#4,#5),$,#7);\n";
    ifc << "ENDSEC;\nEND-ISO-10303-21;\n";
    fbv::ConvertOptions systems;
    systems.output = (root / "systems").string();
    systems.as_directory = true;
    systems.source_name = "systems.ifc";
    systems.mesher = "analytic";
    const auto systems_status = fbv::convert_text(ifc.str(), systems);
    if (systems_status.code != 0) std::cerr << systems_status.error << "\n";
    CHECK(systems_status.code == 0);
    CHECK(systems_status.elements == 2);
    char systems_err[512] = {};
    fbv_package* systems_pkg =
        fbv_package_open(systems.output.c_str(), systems_err, sizeof(systems_err));
    if (systems_pkg == nullptr) std::cerr << systems_err << "\n";
    CHECK(systems_pkg != nullptr);
    if (systems_pkg != nullptr) {
      fbv_manifest_info systems_info{};
      CHECK(fbv_package_manifest(systems_pkg, &systems_info) == FBV_OK);
      CHECK(systems_info.format_version == 4);
      fbv_package_close(systems_pkg);
    }
    fbv::SqliteDb db(std::filesystem::path(systems.output) / "meta.sqlite", false);
    {
      auto tile_disc = db.prepare(
          "SELECT e.name, t.discipline, t.storey_id IS NULL FROM elements e "
          "JOIN tile_elements te ON te.element_id = e.id "
          "JOIN tiles t ON t.id = te.tile_id ORDER BY e.name");
      CHECK(tile_disc.step_row());
      CHECK(std::string(tile_disc.column_text(0)) == "Column out");
      CHECK(std::string(tile_disc.column_text(1)) == "structure");
      CHECK(tile_disc.column_int64(2) == 1);
      CHECK(tile_disc.step_row());
      CHECK(std::string(tile_disc.column_text(0)) == "Wall in system");
      CHECK(std::string(tile_disc.column_text(1)) == "heating");
      CHECK(tile_disc.column_int64(2) == 1);
      auto names = db.prepare(
          "SELECT s.name, e.name FROM system_elements se "
          "JOIN systems s ON s.id = se.system_id "
          "JOIN elements e ON e.id = se.element_id "
          "ORDER BY s.name, e.name");
      CHECK(names.step_row());
      CHECK(names.column_text(0) == "Heating");
      CHECK(names.column_text(1) == "Wall in system");
      CHECK(names.step_row());
      CHECK(names.column_text(0) == "Structure");
      CHECK(names.column_text(1) == "Column out");
      CHECK(names.step_row());
      CHECK(names.column_text(0) == "Structure");
      CHECK(names.column_text(1) == "Wall in system");
      CHECK(!names.step_row());
    }
    std::string systems_report;
    CHECK(fbv::validate_package(systems.output, systems_report) == 0);

    db.close();
    fbv::SqliteDb writable(std::filesystem::path(systems.output) / "meta.sqlite", true);
    writable.exec("DROP TABLE systems");
    writable.close();
    const auto sqlite_path = std::filesystem::path(systems.output) / "meta.sqlite";
    const std::string broken_hash = fbv::sha256_file(sqlite_path);
    std::string manifest_text =
        fbv::read_text(std::filesystem::path(systems.output) / "manifest.json");
    const auto hash_at = manifest_text.find("\"meta.sqlite\"");
    CHECK(hash_at != std::string::npos);
    const auto sha_key = manifest_text.find("\"sha256\"", hash_at);
    CHECK(sha_key != std::string::npos);
    const auto sha_quote = manifest_text.find('"', sha_key + 8);
    CHECK(sha_quote != std::string::npos);
    manifest_text.replace(sha_quote + 1, 64, broken_hash);
    const auto bytes_key = manifest_text.find("\"bytes\"", sha_key);
    CHECK(bytes_key != std::string::npos);
    const auto bytes_colon = manifest_text.find(':', bytes_key);
    const auto bytes_number = manifest_text.find_first_of("0123456789", bytes_colon);
    const auto bytes_end = manifest_text.find_first_not_of("0123456789", bytes_number);
    manifest_text.replace(bytes_number, bytes_end - bytes_number,
                          std::to_string(std::filesystem::file_size(sqlite_path)));
    fbv::write_text(std::filesystem::path(systems.output) / "manifest.json", manifest_text);
    char broken_err[512] = {};
    fbv_package* broken = fbv_package_open(systems.output.c_str(), broken_err, sizeof(broken_err));
    CHECK(broken == nullptr);
    CHECK(std::string(broken_err).find("missing table systems") != std::string::npos);
    std::string broken_report;
    CHECK(fbv::validate_package(systems.output, broken_report) != 0);
    CHECK(broken_report.find("missing table systems") != std::string::npos);
  }

  if (g_failed != 0) {
    std::cerr << g_failed << " converter checks failed\n";
    return 1;
  }
  std::cout << "converter_tests ok\n";
  return 0;
}
