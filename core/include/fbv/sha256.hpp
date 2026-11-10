#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>

namespace fbv {

struct Sha256 {
  std::array<uint8_t, 32> bytes{};
};

Sha256 sha256_bytes(const uint8_t* data, std::size_t len);
Sha256 sha256_bytes(std::string_view data);
std::string sha256_hex(const Sha256& digest);
std::string sha256_file(const std::filesystem::path& path);

}  // namespace fbv
