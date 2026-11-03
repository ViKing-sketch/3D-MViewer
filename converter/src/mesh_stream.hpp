#pragma once

#include "scene.hpp"

namespace fbv {

std::uint64_t mesh_buffer_bytes(const TriMesh& mesh);

// Counts the mesh toward the RAM budget and spills it to disk when the budget
// is exceeded. Positions stay in world metres; the package writer shifts them.
void commit_mesh(Scene& scene, Element& element, const ConvertOptions& options);

// Loads a spilled mesh and subtracts the local origin once.
void prepare_mesh_for_write(Scene& scene, Element& element);

// Drops the in-memory copy. A scratch file, if any, is kept.
void release_mesh_ram(Element& element);

// Drops RAM and the scratch file. Used when a mesher result is discarded.
void discard_element_mesh(Scene& scene, Element& element);

void clear_mesh_scratch(Scene& scene);

// Loads a spilled mesh back into RAM without shifting it.
void reload_mesh_world(Scene& scene, Element& element);

}  // namespace fbv
