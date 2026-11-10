// Android OCCT probe executable. The same measurement lives in probe_run.cpp
// and is also called from the JNI library. This binary does not read or write
// a .fbvpkg package.

#include "probe_run.hpp"

#include <csignal>
#include <cstdio>
#include <unistd.h>

namespace {

void on_signal(int sig) {
  char buf[32];
  buf[0] = 'm';
  buf[1] = 'a';
  buf[2] = 'r';
  buf[3] = 'k';
  buf[4] = 'e';
  buf[5] = 'r';
  buf[6] = ' ';
  buf[7] = 's';
  buf[8] = 'i';
  buf[9] = 'g';
  buf[10] = 'n';
  buf[11] = 'a';
  buf[12] = 'l';
  buf[13] = ' ';
  buf[14] = static_cast<char>('0' + (sig / 10) % 10);
  buf[15] = static_cast<char>('0' + sig % 10);
  buf[16] = '\n';
  const ssize_t wrote = ::write(STDOUT_FILENO, buf, 17);
  (void)wrote;
  std::signal(sig, SIG_DFL);
  raise(sig);
}

// Runs after DT_NEEDED constructors (including OCCT) and before main.
void exe_init() __attribute__((constructor));
void exe_init() {
  static const char line[] = "marker exe_init\n";
  const ssize_t wrote = ::write(STDOUT_FILENO, line, sizeof line - 1);
  (void)wrote;
  std::signal(SIGSEGV, on_signal);
  std::signal(SIGABRT, on_signal);
  std::signal(SIGBUS, on_signal);
}

}  // namespace

int main(int argc, char** argv) {
  const char* brep = argc > 1 ? argv[1] : "fbv-occt-box.bin";
  const char* trace = argc > 2 ? argv[2] : nullptr;
  const ProbeResult result = occt_probe_run(brep, trace);
  return result.code;
}
