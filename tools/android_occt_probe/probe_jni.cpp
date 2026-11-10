#include "probe_run.hpp"

#include <jni.h>

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

}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_fieldbim_occtprobe_JniProbeService_nativeRun(JNIEnv* env, jobject, jstring brep,
                                                      jstring trace) {
  return run_probe(env, brep, trace);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_fieldbim_field_bim_viewer_OcctProbe_nativeRun(JNIEnv* env, jobject, jstring brep,
                                                       jstring trace) {
  return run_probe(env, brep, trace);
}
