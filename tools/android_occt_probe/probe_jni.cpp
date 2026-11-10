#include "probe_run.hpp"

#include <BinTools.hxx>
#include <TopoDS_Shape.hxx>
#include <jni.h>

#include <chrono>
#include <fstream>
#include <string>

namespace {

jstring run_probe(JNIEnv* env, jstring brep, jstring trace) {
  const char* brep_path = brep != nullptr ? env->GetStringUTFChars(brep, nullptr) : nullptr;
  const char* trace_path = trace != nullptr ? env->GetStringUTFChars(trace, nullptr) : nullptr;
  const ProbeResult result = occt_probe_run(brep_path, trace_path);
  if (brep != nullptr) env->ReleaseStringUTFChars(brep, brep_path);
  if (trace != nullptr) env->ReleaseStringUTFChars(trace, trace_path);
  const std::string text = result.text + "exit=" + std::to_string(result.code) + "\n";
  return env->NewStringUTF(text.c_str());
}

std::string read_brep_text(const char* path, int max_bytes, int max_ms) {
  if (path == nullptr || path[0] == '\0') return "read=fail reason=read\n";
  std::ifstream in(path, std::ios::binary);
  if (!in) return "read=fail reason=read\n";
  in.seekg(0, std::ios::end);
  const auto size = static_cast<long long>(in.tellg());
  in.seekg(0, std::ios::beg);
  if (size <= 0) return "read=fail reason=read\n";
  if (max_bytes > 0 && size > max_bytes) {
    return "read=fail reason=memory bytes=" + std::to_string(size) + "\n";
  }
  const auto started = std::chrono::steady_clock::now();
  TopoDS_Shape shape;
  try {
    BinTools::Read(shape, in);
  } catch (const std::exception& ex) {
    return std::string("read=fail reason=read ") + ex.what() + "\n";
  } catch (...) {
    return "read=fail reason=read\n";
  }
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now() - started)
                           .count();
  if (shape.IsNull()) return "read=fail reason=read\n";
  if (max_ms > 0 && elapsed > max_ms) {
    return "read=fail reason=time elapsed_ms=" + std::to_string(elapsed) + "\n";
  }
  return "read=ok bytes=" + std::to_string(size) + " elapsed_ms=" + std::to_string(elapsed) +
         "\n";
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_fieldbim_occtprobe_JniProbeService_nativeRun(JNIEnv* env, jobject, jstring brep,
                                                      jstring trace) {
  return run_probe(env, brep, trace);
}

// The viewer package is com.fieldbim.field_bim_viewer. JNI encodes each '_' in
// a class name as "_1", so the exported symbol is field_1bim_1viewer. The
// unescaped name field_bim_viewer loads the .so and then fails with
// UnsatisfiedLinkError on the phone.
extern "C" JNIEXPORT jstring JNICALL
Java_com_fieldbim_field_1bim_1viewer_OcctProbe_nativeRun(JNIEnv* env, jobject, jstring brep,
                                                         jstring trace) {
  return run_probe(env, brep, trace);
}

// Same underscore encoding as nativeRun. A failed BinTools read returns a
// reason string. It does not abort the process; the viewer then uses the mesh.
extern "C" JNIEXPORT jstring JNICALL
Java_com_fieldbim_field_1bim_1viewer_OcctProbe_nativeReadBrep(JNIEnv* env, jobject, jstring path,
                                                              jint max_bytes, jint max_ms) {
  const char* chars = path != nullptr ? env->GetStringUTFChars(path, nullptr) : nullptr;
  const std::string text = read_brep_text(chars, max_bytes, max_ms);
  if (path != nullptr) env->ReleaseStringUTFChars(path, chars);
  return env->NewStringUTF(text.c_str());
}
