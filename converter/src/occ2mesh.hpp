#pragma once

#include <string>

namespace fbv {

// Future OCCT BRepMesh pipeline (task Z05). The MVP mesher is analytic and does not call this.
struct Occ2MeshStatus {
  bool ok = false;
  std::string error =
      "occ2mesh requires OCCT 7.8.1 (configure -DFBV_WITH_OCCT=ON after the superbuild)";
};

}  // namespace fbv
