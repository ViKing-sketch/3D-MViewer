#pragma once

#include <string>

namespace fbv {

// Future STEP importer on OCCT XDE (task Z06). MVP rejects STEP/IGES with this explanation.
struct XdeImportStatus {
  bool ok = false;
  std::string error =
      "STEP/IGES import requires OCCT XDE 7.8.1 (configure -DFBV_WITH_OCCT=ON after the "
      "superbuild)";
};

}  // namespace fbv
