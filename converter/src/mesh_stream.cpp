#include "mesh_stream.hpp"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <stdexcept>

namespace fbv {
namespace {

constexpr std::uint32_t kMeshMagic = 0x314D4246u;  // 'FBM1' little-endian

std::filesystem::path make_scratch_dir() {
  const auto base = std::filesystem::temp_directory_path();
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  for (int i = 0; i < 1000; ++i) {
    auto path = base / ("fbvmesh-" + std::to_string(stamp) + "-" + std::to_string(i));
    if (std::filesystem::create_directory(path)) return path;
  }
  throw std::runtime_error("cannot create a mesh scratch directory");
}

void write_u32(std::ostream& out, std::uint32_t value) {
  char bytes[4];
  for (int i = 0; i < 4; ++i) bytes[i] = static_cast<char>((value >> (8 * i)) & 0xff);
  out.write(bytes, 4);
}

std::uint32_t read_u32(std::istream& in) {
  unsigned char bytes[4];
  in.read(reinterpret_cast<char*>(bytes), 4);
  if (!in) throw std::runtime_error("truncated mesh scratch file");
  return static_cast<std::uint32_t>(bytes[0]) | (static_cast<std::uint32_t>(bytes[1]) << 8) |
         (static_cast<std::uint32_t>(bytes[2]) << 16) |
         (static_cast<std::uint32_t>(bytes[3]) << 24);
}

template <typename T>
void write_pod(std::ostream& out, const std::vector<T>& values) {
  if (values.empty()) return;
  out.write(reinterpret_cast<const char*>(values.data()),
            static_cast<std::streamsize>(values.size() * sizeof(T)));
}

template <typename T>
void read_pod(std::istream& in, std::vector<T>& values, std::uint32_t count) {
  values.resize(count);
  if (count == 0) return;
  in.read(reinterpret_cast<char*>(values.data()),
          static_cast<std::streamsize>(static_cast<std::size_t>(count) * sizeof(T)));
  if (!in) throw std::runtime_error("truncated mesh scratch file");
}

std::uint32_t checked_count(std::size_t count, const char* what) {
  if (count > static_cast<std::size_t>(UINT32_MAX))
    throw std::runtime_error(std::string("mesh ") + what + " does not fit in a scratch file");
  return static_cast<std::uint32_t>(count);
}

void account(Scene& scene, Element& element) {
  const auto bytes = mesh_buffer_bytes(element.mesh);
  if (bytes >= element.mesh_accounted_bytes)
    scene.mesh_resident_bytes += bytes - element.mesh_accounted_bytes;
  else
    scene.mesh_resident_bytes -= element.mesh_accounted_bytes - bytes;
  element.mesh_accounted_bytes = bytes;
  if (scene.mesh_resident_bytes > scene.mesh_bytes_peak)
    scene.mesh_bytes_peak = scene.mesh_resident_bytes;
}

void load_scratch(Element& element) {
  std::ifstream in(element.mesh_scratch, std::ios::binary);
  if (!in) throw std::runtime_error("cannot read mesh scratch " + element.mesh_scratch);
  const std::uint32_t magic = read_u32(in);
  if (magic != kMeshMagic) throw std::runtime_error("bad mesh scratch " + element.mesh_scratch);
  const std::uint32_t npos = read_u32(in);
  const std::uint32_t nrm = read_u32(in);
  const std::uint32_t nidx = read_u32(in);
  read_pod(in, element.mesh.position, npos);
  read_pod(in, element.mesh.normal, nrm);
  read_pod(in, element.mesh.indices, nidx);
  element.mesh_local = false;
}

void spill(Scene& scene, Element& element) {
  if (scene.mesh_scratch_dir.empty()) scene.mesh_scratch_dir = make_scratch_dir().string();
  const auto path =
      std::filesystem::path(scene.mesh_scratch_dir) / ("e" + std::to_string(element.id) + ".fbm");
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) throw std::runtime_error("cannot write mesh scratch " + path.string());
  write_u32(out, kMeshMagic);
  write_u32(out, checked_count(element.mesh.position.size(), "positions"));
  write_u32(out, checked_count(element.mesh.normal.size(), "normals"));
  write_u32(out, checked_count(element.mesh.indices.size(), "indices"));
  write_pod(out, element.mesh.position);
  write_pod(out, element.mesh.normal);
  write_pod(out, element.mesh.indices);
  if (!out) throw std::runtime_error("cannot finish mesh scratch " + path.string());
  out.close();
  element.mesh_scratch = path.string();
  if (scene.mesh_resident_bytes >= element.mesh_accounted_bytes)
    scene.mesh_resident_bytes -= element.mesh_accounted_bytes;
  else
    scene.mesh_resident_bytes = 0;
  element.mesh_accounted_bytes = 0;
  element.mesh = TriMesh{};
  element.mesh_local = false;
}

}  // namespace

std::uint64_t mesh_buffer_bytes(const TriMesh& mesh) {
  return mesh.position.size() * sizeof(double) + mesh.normal.size() * sizeof(double) +
         mesh.indices.size() * sizeof(std::uint32_t);
}

void reload_mesh_world(Scene& scene, Element& element) {
  if (!element.mesh.position.empty() || element.mesh_scratch.empty()) return;
  load_scratch(element);
  account(scene, element);
}

void commit_mesh(Scene& scene, Element& element, const ConvertOptions& options) {
  if (element.mesh.indices.empty() && element.mesh_scratch.empty()) return;
  if (element.mesh.indices.empty()) return;
  element.triangle_count = static_cast<int>(element.mesh.indices.size() / 3);
  for (std::size_t i = 0; i + 2 < element.mesh.position.size(); i += 3) {
    expand_bbox(element, {element.mesh.position[i], element.mesh.position[i + 1],
                          element.mesh.position[i + 2]});
  }
  account(scene, element);
  if (scene.mesh_resident_bytes > mesh_budget_bytes(options)) {
    spill(scene, element);
    return;
  }
  // A later representation may pull a spilled mesh back under the budget.
  // The scratch file would still be the shorter mesh and would replace this
  // one on the next read.
  if (!element.mesh_scratch.empty()) {
    std::error_code ec;
    std::filesystem::remove(element.mesh_scratch, ec);
    element.mesh_scratch.clear();
  }
}

void prepare_mesh_for_write(Scene& scene, Element& element) {
  if (element.mesh.position.empty() && !element.mesh_scratch.empty()) load_scratch(element);
  if (element.mesh_local) return;
  if (scene.has_world) {
    for (std::size_t i = 0; i + 2 < element.mesh.position.size(); i += 3) {
      element.mesh.position[i] -= scene.origin.x;
      element.mesh.position[i + 1] -= scene.origin.y;
      element.mesh.position[i + 2] -= scene.origin.z;
    }
  }
  element.mesh_local = true;
}

void release_mesh_ram(Element& element) {
  element.mesh = TriMesh{};
  element.mesh_local = false;
  element.mesh_accounted_bytes = 0;
}

void discard_element_mesh(Scene& scene, Element& element) {
  if (scene.mesh_resident_bytes >= element.mesh_accounted_bytes)
    scene.mesh_resident_bytes -= element.mesh_accounted_bytes;
  else
    scene.mesh_resident_bytes = 0;
  element.mesh_accounted_bytes = 0;
  if (!element.mesh_scratch.empty()) {
    std::error_code ec;
    std::filesystem::remove(element.mesh_scratch, ec);
    element.mesh_scratch.clear();
  }
  element.mesh = TriMesh{};
  element.mesh_local = false;
  element.triangle_count = 0;
  element.has_mesh = false;
  element.mesh_source.clear();
}

void clear_mesh_scratch(Scene& scene) {
  if (!scene.mesh_scratch_dir.empty()) {
    std::error_code ec;
    std::filesystem::remove_all(scene.mesh_scratch_dir, ec);
    scene.mesh_scratch_dir.clear();
  }
  for (Element& element : scene.elements) element.mesh_scratch.clear();
}

}  // namespace fbv
