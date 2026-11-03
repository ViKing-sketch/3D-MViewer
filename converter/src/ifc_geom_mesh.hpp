#pragma once

#include "scene.hpp"

namespace fbv {

// Primary mesher. When this build has IfcOpenShell, runs the geometry iterator
// on the Open CASCADE kernel and writes triangle meshes onto matching elements.
// Otherwise it leaves the scene for the analytic extrusion fallback.
void apply_ifcopenshell_geometry(Scene& scene, const std::string& ifc_text,
                                 const ConvertOptions& options);

}  // namespace fbv
