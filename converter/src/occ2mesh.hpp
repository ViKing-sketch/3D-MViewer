#pragma once

#include <string>

namespace fbv {

// OCCT triangulation of IFC runs through IfcOpenShell (ifc_geom_mesh.cpp) when
// FBV_WITH_IFCOPENSHELL is on. This status remains for a direct BRepMesh call.
struct Occ2MeshStatus {
  bool ok = false;
  std::string error =
      "occ2mesh requires OCCT 7.8.1 (configure -DFBV_WITH_OCCT=ON after the superbuild)";
};

}  // namespace fbv
