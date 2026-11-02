#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fbv {

struct ZipItem {
  std::string name;
  std::vector<std::uint8_t> bytes;
};

// STORE-method ZIP (no compression). Entry names use '/'.
bool write_zip_stored(const std::vector<ZipItem>& items, const std::filesystem::path& dest,
                      std::string& error);
bool zip_directory_stored(const std::filesystem::path& directory, const std::filesystem::path& dest,
                          std::string& error);
bool unzip_stored(const std::filesystem::path& zip_file, const std::filesystem::path& dest,
                  std::string& error);

std::uint32_t crc32_bytes(const std::uint8_t* data, std::size_t len);

}  // namespace fbv
