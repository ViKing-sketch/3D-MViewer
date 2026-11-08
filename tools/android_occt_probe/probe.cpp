// Android OCCT probe. Builds a box, measures its exact volume and area, and
// writes that shape through BinTools and back. The temporary file is removed.
// This binary does not read or write a .fbvpkg package.

#include <BinTools.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <TopoDS_Shape.hxx>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <string>

namespace {

long hwm_kb() {
  FILE* file = std::fopen("/proc/self/status", "r");
  if (file == nullptr) return -1;
  char line[256];
  long hwm = -1;
  while (std::fgets(line, sizeof line, file) != nullptr) {
    if (std::sscanf(line, "VmHWM: %ld", &hwm) == 1) break;
  }
  std::fclose(file);
  return hwm;
}

bool near(double value, double expected, double tol) {
  return std::fabs(value - expected) <= tol;
}

}  // namespace

int main(int argc, char** argv) {
  const char* path = argc > 1 ? argv[1] : "fbv-occt-box.bin";
  const auto started = std::chrono::steady_clock::now();

  // 1 m by 2 m by 3 m. Exact volume is 6 m^3. Exact surface area is 22 m^2.
  const TopoDS_Shape box = BRepPrimAPI_MakeBox(1.0, 2.0, 3.0).Shape();
  GProp_GProps volume;
  BRepGProp::VolumeProperties(box, volume);
  GProp_GProps area;
  BRepGProp::SurfaceProperties(box, area);
  if (!near(volume.Mass(), 6.0, 1e-9)) {
    std::fprintf(stderr, "volume mismatch %.17g\n", volume.Mass());
    return 2;
  }
  if (!near(area.Mass(), 22.0, 1e-7)) {
    std::fprintf(stderr, "area mismatch %.17g\n", area.Mass());
    return 3;
  }

  if (!BinTools::Write(box, path)) {
    std::fprintf(stderr, "bintools write failed\n");
    return 4;
  }
  std::ifstream in(path, std::ios::binary | std::ios::ate);
  if (!in) {
    std::fprintf(stderr, "bintools file missing\n");
    return 4;
  }
  const auto bytes = static_cast<long long>(in.tellg());
  in.close();

  TopoDS_Shape restored;
  if (!BinTools::Read(restored, path)) {
    std::fprintf(stderr, "bintools read failed\n");
    return 5;
  }
  std::remove(path);

  GProp_GProps again;
  BRepGProp::VolumeProperties(restored, again);
  if (!near(again.Mass(), 6.0, 1e-9)) {
    std::fprintf(stderr, "round-trip volume %.17g\n", again.Mass());
    return 6;
  }

  const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now() - started);
  std::printf(
      "ok volume_m3=6 area_m2=22 bintools_bytes=%lld elapsed_us=%lld rss_hwm_kb=%ld\n",
      bytes, static_cast<long long>(elapsed.count()), hwm_kb());
  return 0;
}
