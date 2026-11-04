import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

bool _configured = false;
bool _androidPrepared = false;

/// Loads the bundled Android `libsqlite3.so` before any database is opened.
///
/// Dart FFI looks the library up by name. Without [sqlite3_flutter_libs] the
/// APK does not contain it (`dlopen libsqlite3.so not found` on API 36). On
/// older Android the Java loader has to map it before FFI can open it.
Future<void> prepareSqlite() async {
  if (_androidPrepared || !Platform.isAndroid) {
    configureSqlite();
    return;
  }
  _androidPrepared = true;
  await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  configureSqlite();
}

void configureSqlite() {
  if (_configured) return;
  _configured = true;
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, () => DynamicLibrary.open('libsqlite3.so'));
    return;
  }
  if (!Platform.isLinux) return;
  open.overrideFor(OperatingSystem.linux, () {
    for (final name in ['libsqlite3.so.0', 'libsqlite3.so']) {
      try {
        return DynamicLibrary.open(name);
      } on ArgumentError {
        continue;
      }
    }
    throw StateError('libsqlite3 was not found. Install the system SQLite library.');
  });
}
