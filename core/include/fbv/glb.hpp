#pragma once

#include "fbv/json.hpp"

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fbv {

struct GlbContents {
  Json json;
  std::vector<std::uint8_t> bin;
};

bool read_glb(const std::filesystem::path& path, GlbContents& out, std::string& error);
bool parse_glb(const std::uint8_t* data, std::size_t len, GlbContents& out, std::string& error);

// Concatenated POSITION accessors (float xyz).
bool glb_positions(const GlbContents& glb, std::vector<float>& xyz, std::string& error);

// elementId values stored in node extras.
std::vector<std::int64_t> glb_element_ids(const GlbContents& glb);

}  // namespace fbv
