#include "fbv/glb.hpp"

#include "fbv/io.hpp"

#include <cstring>

namespace fbv {
namespace {

std::uint32_t read_u32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24));
}

const Json* obj_field(const Json& json, const std::string& key) {
  if (json.type != Json::Type::Object) return nullptr;
  return json.find(key);
}

}  // namespace

bool parse_glb(const std::uint8_t* data, std::size_t len, GlbContents& out, std::string& error) {
  if (len < 20) {
    error = "glb is too small";
    return false;
  }
  if (std::memcmp(data, "glTF", 4) != 0) {
    error = "glb magic is not glTF";
    return false;
  }
  const std::uint32_t version = read_u32(data + 4);
  const std::uint32_t length = read_u32(data + 8);
  if (version != 2) {
    error = "glb version is not 2";
    return false;
  }
  if (length != len) {
    error = "glb length does not match the file";
    return false;
  }
  std::size_t offset = 12;
  bool saw_json = false;
  out.bin.clear();
  while (offset + 8 <= len) {
    const std::uint32_t chunk_len = read_u32(data + offset);
    const std::uint32_t chunk_type = read_u32(data + offset + 4);
    offset += 8;
    if (offset + chunk_len > len) {
      error = "glb chunk exceeds the file";
      return false;
    }
    if (chunk_type == 0x4E4F534Au) {
      const std::string text(reinterpret_cast<const char*>(data + offset), chunk_len);
      if (!Json::parse(text, out.json, error)) return false;
      saw_json = true;
    } else if (chunk_type == 0x004E4942u) {
      out.bin.assign(data + offset, data + offset + chunk_len);
    }
    offset += chunk_len;
  }
  if (!saw_json) {
    error = "glb has no JSON chunk";
    return false;
  }
  return true;
}

bool read_glb(const std::filesystem::path& path, GlbContents& out, std::string& error) {
  try {
    const auto bytes = read_binary(path);
    return parse_glb(bytes.data(), bytes.size(), out, error);
  } catch (const std::exception& ex) {
    error = ex.what();
    return false;
  }
}

bool glb_positions(const GlbContents& glb, std::vector<float>& xyz, std::string& error) {
  xyz.clear();
  const Json* views = obj_field(glb.json, "bufferViews");
  const Json* accessors = obj_field(glb.json, "accessors");
  const Json* meshes = obj_field(glb.json, "meshes");
  if (views == nullptr || accessors == nullptr || meshes == nullptr) return true;
  if (meshes->type != Json::Type::Array) {
    error = "glb meshes is not an array";
    return false;
  }
  for (const Json& mesh : meshes->arr) {
    const Json* prims = obj_field(mesh, "primitives");
    if (prims == nullptr || prims->arr.empty()) continue;
    const Json* attrs = obj_field(prims->arr[0], "attributes");
    const Json* pos_index = attrs != nullptr ? obj_field(*attrs, "POSITION") : nullptr;
    if (pos_index == nullptr) continue;
    const auto index = static_cast<std::size_t>(pos_index->as_int(-1));
    if (pos_index->as_int(-1) < 0 || index >= accessors->arr.size()) {
      error = "glb POSITION accessor is out of range";
      return false;
    }
    const Json& acc = accessors->arr[index];
    const int view_index = static_cast<int>(
        obj_field(acc, "bufferView") != nullptr ? obj_field(acc, "bufferView")->as_int(-1) : -1);
    if (view_index < 0 || static_cast<std::size_t>(view_index) >= views->arr.size()) {
      error = "glb bufferView is out of range";
      return false;
    }
    const Json& view = views->arr[static_cast<std::size_t>(view_index)];
    const auto view_off = static_cast<std::size_t>(
        obj_field(view, "byteOffset") != nullptr ? obj_field(view, "byteOffset")->as_int(0) : 0);
    const auto acc_off = static_cast<std::size_t>(
        obj_field(acc, "byteOffset") != nullptr ? obj_field(acc, "byteOffset")->as_int(0) : 0);
    const auto count = static_cast<std::size_t>(
        obj_field(acc, "count") != nullptr ? obj_field(acc, "count")->as_int(0) : 0);
    const std::size_t start = view_off + acc_off;
    const std::size_t bytes = count * 3 * sizeof(float);
    if (start + bytes > glb.bin.size()) {
      error = "glb positions exceed the BIN chunk";
      return false;
    }
    const float* ptr = reinterpret_cast<const float*>(glb.bin.data() + start);
    xyz.insert(xyz.end(), ptr, ptr + count * 3);
  }
  return true;
}

std::vector<std::int64_t> glb_element_ids(const GlbContents& glb) {
  std::vector<std::int64_t> ids;
  const Json* nodes = obj_field(glb.json, "nodes");
  if (nodes == nullptr || nodes->type != Json::Type::Array) return ids;
  for (const Json& node : nodes->arr) {
    const Json* extras = obj_field(node, "extras");
    if (extras == nullptr) continue;
    const Json* element = obj_field(*extras, "elementId");
    if (element != nullptr && element->type == Json::Type::Number) ids.push_back(element->as_int());
  }
  return ids;
}

}  // namespace fbv
