import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

bool _configured = false;

void configureSqlite() {
  if (_configured) return;
  _configured = true;
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    for (final name in ['libsqlite3.so.0', 'libsqlite3.so']) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    throw StateError('libsqlite3 was not found. Install the system SQLite library.');
  });
}
