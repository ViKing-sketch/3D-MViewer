#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fbv {

std::vector<std::uint8_t> read_binary(const std::filesystem::path& path);
void write_binary(const std::filesystem::path& path, const std::uint8_t* data, std::size_t len);
void write_binary(const std::filesystem::path& path, const std::vector<std::uint8_t>& data);
void write_text(const std::filesystem::path& path, const std::string& text);
std::string read_text(const std::filesystem::path& path);

}  // namespace fbv
