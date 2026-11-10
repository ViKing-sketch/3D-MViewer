#include "fbv/io.hpp"

#include <fstream>
#include <stdexcept>

namespace fbv {

std::vector<std::uint8_t> read_binary(const std::filesystem::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("cannot read " + path.string());
  return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(in),
                                   std::istreambuf_iterator<char>());
}

void write_binary(const std::filesystem::path& path, const std::uint8_t* data, std::size_t len) {
  if (path.has_parent_path()) std::filesystem::create_directories(path.parent_path());
  std::ofstream out(path, std::ios::binary);
  if (!out) throw std::runtime_error("cannot write " + path.string());
  if (len != 0) out.write(reinterpret_cast<const char*>(data), static_cast<std::streamsize>(len));
  if (!out) throw std::runtime_error("failed while writing " + path.string());
}

void write_binary(const std::filesystem::path& path, const std::vector<std::uint8_t>& data) {
  write_binary(path, data.data(), data.size());
}

void write_text(const std::filesystem::path& path, const std::string& text) {
  write_binary(path, reinterpret_cast<const std::uint8_t*>(text.data()), text.size());
}

std::string read_text(const std::filesystem::path& path) {
  const auto bytes = read_binary(path);
  return std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size());
}

}  // namespace fbv
