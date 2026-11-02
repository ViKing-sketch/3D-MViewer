#pragma once

#include "scene.hpp"

#include "fbv/convert.hpp"

#include <string>

namespace fbv {

void write_scene_package(Scene& scene, const ConvertOptions& options,
                         const std::string& source_bytes, const std::string& source_name);

}  // namespace fbv
