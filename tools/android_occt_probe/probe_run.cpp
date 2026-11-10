#include "probe_run.hpp"

#include <BinTools.hxx>
#include <BRepGProp.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <GProp_GProps.hxx>
#include <Standard_Failure.hxx>
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

class Trace {
 public:
  explicit Trace(const char* path) {
    if (path != nullptr && path[0] != '\0') {
      file_ = std::fopen(path, "w");
    }
  }
  ~Trace() {
    if (file_ != nullptr) std::fclose(file_);
  }
  void mark(const std::string& line) {
    text_ += line;
    text_ += '\n';
    std::fputs(line.c_str(), stdout);
    std::fputc('\n', stdout);
    std::fflush(stdout);
    if (file_ != nullptr) {
      std::fputs(line.c_str(), file_);
      std::fputc('\n', file_);
      std::fflush(file_);
    }
  }
  const std::string& text() const { return text_; }

 private:
  FILE* file_ = nullptr;
  std::string text_;
};

}  // namespace

ProbeResult occt_probe_run(const char* brep_path, const char* log_path) {
  Trace trace(log_path);
  const char* path = (brep_path != nullptr && brep_path[0] != '\0') ? brep_path : "fbv-occt-box.bin";
  try {
    trace.mark("marker main before_occt");
    const auto started = std::chrono::steady_clock::now();

    // 1 m by 2 m by 3 m. Exact volume is 6 m^3. Exact surface area is 22 m^2.
    const TopoDS_Shape box = BRepPrimAPI_MakeBox(1.0, 2.0, 3.0).Shape();
    trace.mark("marker box");
    GProp_GProps volume;
    BRepGProp::VolumeProperties(box, volume);
    trace.mark("marker volume " + std::to_string(volume.Mass()));
    GProp_GProps area;
    BRepGProp::SurfaceProperties(box, area);
    trace.mark("marker area " + std::to_string(area.Mass()));
    if (!near(volume.Mass(), 6.0, 1e-9)) {
      trace.mark("volume mismatch " + std::to_string(volume.Mass()));
      return ProbeResult{2, trace.text()};
    }
    if (!near(area.Mass(), 22.0, 1e-7)) {
      trace.mark("area mismatch " + std::to_string(area.Mass()));
      return ProbeResult{3, trace.text()};
    }

    if (!BinTools::Write(box, path)) {
      trace.mark("marker bintools_write failed");
      return ProbeResult{4, trace.text()};
    }
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) {
      trace.mark("marker bintools_file missing");
      return ProbeResult{4, trace.text()};
    }
    const auto bytes = static_cast<long long>(in.tellg());
    in.close();
    trace.mark("marker bintools_write bytes=" + std::to_string(bytes));

    TopoDS_Shape restored;
    if (!BinTools::Read(restored, path)) {
      trace.mark("marker bintools_read failed");
      return ProbeResult{5, trace.text()};
    }
    std::remove(path);
    trace.mark("marker bintools_read");

    GProp_GProps again;
    BRepGProp::VolumeProperties(restored, again);
    if (!near(again.Mass(), 6.0, 1e-9)) {
      trace.mark("round-trip volume " + std::to_string(again.Mass()));
      return ProbeResult{6, trace.text()};
    }
    trace.mark("marker roundtrip");

    const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now() - started);
    char done[160];
    std::snprintf(done, sizeof done,
                  "ok volume_m3=6 area_m2=22 bintools_bytes=%lld elapsed_us=%lld rss_hwm_kb=%ld",
                  bytes, static_cast<long long>(elapsed.count()), hwm_kb());
    trace.mark(done);
    return ProbeResult{0, trace.text()};
  } catch (const Standard_Failure& error) {
    const char* message = error.GetMessageString();
    trace.mark(std::string("marker occt_exception ") + (message != nullptr ? message : ""));
    return ProbeResult{7, trace.text()};
  } catch (const std::exception& error) {
    trace.mark(std::string("marker exception ") + error.what());
    return ProbeResult{7, trace.text()};
  }
}
