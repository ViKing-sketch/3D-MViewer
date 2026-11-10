#pragma once

#include <string>

// Runs the box probe. Prints each marker to stdout and flushes it, and also
// appends the same line to `log_path` when that path is not null. Library
// constructors run before this function; the first marker is the first line
// of main's own work, before any OCCT call from this file.
struct ProbeResult {
  int code;
  std::string text;
};

ProbeResult occt_probe_run(const char* brep_path, const char* log_path);
