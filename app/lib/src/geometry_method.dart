import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';

import 'model.dart';
import 'occt_probe.dart';

/// Which geometry source the open model uses.
///
/// Priority is fixed and is the order in [decideGeometry]: exact OCCT/BinTools
/// from format v4 `exact_geometry` first. Any failure selects the mesh already
/// stored in the package. `brep.pack` is analytic AABB and is not an input.
/// Walk does not read this value and stays not collision-aware.
enum GeometryMethod { exact, mesh }

class GeometryDecision {
  const GeometryDecision({required this.method, required this.reason});

  final GeometryMethod method;
  final String reason;

  /// One line for logcat and the desktop console.
  String get logLine => 'geometry method=${method.name} reason=$reason';
}

class GeometryFacts {
  const GeometryFacts({
    required this.formatVersion,
    required this.exactBytes,
    required this.abiSupported,
    required this.jniLoaded,
    required this.readOk,
    required this.elapsedMs,
    this.byteLimit = kExactByteLimit,
    this.timeLimitMs = kExactTimeLimitMs,
  });

  final int formatVersion;
  final int exactBytes;
  final bool abiSupported;
  final bool jniLoaded;
  final bool readOk;
  final int elapsedMs;
  final int byteLimit;
  final int timeLimitMs;
}

/// Uncompressed BinTools bytes the viewer will try to read. Larger sums fall
/// back to the mesh without calling OCCT.
const int kExactByteLimit = 32 * 1024 * 1024;

/// Wall-clock budget for one BinTools read. A slower read falls back to the mesh.
const int kExactTimeLimitMs = 2000;

/// Exact geometry only when every earlier check passes. The first failure is
/// the mesh reason.
GeometryDecision decideGeometry(GeometryFacts facts) {
  if (facts.formatVersion < 4) {
    return const GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'old-package',
    );
  }
  if (facts.exactBytes <= 0) {
    return const GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'no-bytes',
    );
  }
  if (facts.exactBytes > facts.byteLimit) {
    return const GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'memory',
    );
  }
  if (!facts.abiSupported) {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'abi');
  }
  if (!facts.jniLoaded) {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'jni');
  }
  if (facts.elapsedMs > facts.timeLimitMs) {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'time');
  }
  if (!facts.readOk) {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'read');
  }
  return const GeometryDecision(
    method: GeometryMethod.exact,
    reason: 'bintools',
  );
}

bool androidArm64() {
  if (!Platform.isAndroid) return false;
  return Abi.current() == Abi.androidArm64;
}

int exactByteTotal(List<ExactGeometry> rows) {
  var total = 0;
  for (final row in rows) {
    if (row.bytes > 0 && row.path.isNotEmpty) total += row.bytes;
  }
  return total;
}

/// The first BinTools file that matches its recorded size, or null when none
/// can be read. A missing or short file is a read failure, not an AABB.
File? firstExactFile(String root, List<ExactGeometry> rows) {
  for (final row in rows) {
    if (row.bytes <= 0 || row.path.isEmpty) continue;
    if (row.path.contains('..')) return null;
    final file = File('$root/${row.path.replaceAll('\\', '/')}');
    if (!file.existsSync()) return null;
    if (file.lengthSync() != row.bytes) return null;
    return file;
  }
  return null;
}

/// Package facts that do not need OCCT. Null means the caller should try a
/// BinTools read. `brep.pack` is not consulted.
GeometryDecision? meshBeforeOcct({
  required int formatVersion,
  required List<ExactGeometry> rows,
  required String root,
  required bool abiSupported,
}) {
  final bytes = exactByteTotal(rows);
  final blocked = decideGeometry(
    GeometryFacts(
      formatVersion: formatVersion,
      exactBytes: bytes,
      abiSupported: abiSupported,
      jniLoaded: true,
      readOk: true,
      elapsedMs: 0,
    ),
  );
  if (blocked.method == GeometryMethod.mesh) return blocked;
  if (firstExactFile(root, rows) == null) {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'read');
  }
  return null;
}

GeometryDecision decisionFromProbe(String text) {
  final reason = RegExp('reason=([a-z]+)').firstMatch(text)?.group(1);
  final elapsed =
      int.tryParse(
        RegExp('elapsed_ms=(\\d+)').firstMatch(text)?.group(1) ?? '',
      ) ??
      0;
  final ok = text.contains('read=ok');
  if (reason == 'memory') {
    return const GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'memory',
    );
  }
  if (reason == 'time') {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'time');
  }
  if (reason == 'jni') {
    return const GeometryDecision(method: GeometryMethod.mesh, reason: 'jni');
  }
  return decideGeometry(
    GeometryFacts(
      formatVersion: 4,
      exactBytes: 1,
      abiSupported: true,
      jniLoaded: reason != 'jni',
      readOk: ok && reason == null,
      elapsedMs: elapsed,
    ),
  );
}

/// Asks OCCT to read one BinTools file. Any failure returns a mesh decision
/// and does not throw.
Future<GeometryDecision> readExactOrMesh(File file) async {
  try {
    final text =
        await OcctProbeChannel.readBrep(
          file.path,
          kExactByteLimit,
          kExactTimeLimitMs,
        ).timeout(
          const Duration(milliseconds: kExactTimeLimitMs + 500),
          onTimeout: () => 'read=fail reason=time\n',
        );
    final decision = decisionFromProbe(text);
    debugPrint(decision.logLine);
    debugPrint(text.trim());
    return decision;
  } catch (error) {
    final decision = const GeometryDecision(
      method: GeometryMethod.mesh,
      reason: 'jni',
    );
    debugPrint(decision.logLine);
    debugPrint('geometry jni $error');
    return decision;
  }
}

class GeometryMethodBanner extends StatelessWidget {
  const GeometryMethodBanner({
    super.key,
    required this.decision,
    required this.label,
  });

  final GeometryDecision decision;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            key: const ValueKey('geometry-method'),
            maxLines: 2,
          ),
        ),
      ),
    );
  }
}
