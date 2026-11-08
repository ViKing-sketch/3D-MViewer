import 'dart:math' as math;

import 'model.dart';
import 'visibility.dart';

/// Standing eye height above the storey floor, in metres.
///
/// This is a fixed viewer height. It is not measured from a person, and it is
/// not a distance to a B-Rep face.
const double kWalkEyeHeight = 1.6;

/// How far the start point stays outside an element box, in metres.
const double kWalkClearance = 0.3;

/// World-metre axis-aligned box from `elements.bbox_*`.
///
/// format_version 1 stores these boxes, and `analytic-box-v1` repeats them in
/// `brep.pack`. The visible mesh is an extrusion or an OCCT triangulation of
/// the same simplified solid. Neither one is a surface the walk can lean on.
class ElementBox {
  const ElementBox({
    required this.id,
    required this.storeyId,
    required this.ifcClass,
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  });

  final int id;
  final int storeyId;
  final String ifcClass;
  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;

  bool get degenerate {
    const eps = 1e-4;
    return (maxX - minX).abs() < eps &&
        (maxY - minY).abs() < eps &&
        (maxZ - minZ).abs() < eps;
  }
}

/// Slabs define the floor. Other classes are obstacles only when the eye
/// height passes through their box.
bool isWalkFloor(String ifcClass) {
  return ifcClass.toLowerCase().startsWith('ifcslab');
}

/// Where the walker stands, in package Z-up world metres.
///
/// [clearOfSolids] is only the start. Later steps do not test these boxes.
class WalkPose {
  const WalkPose({
    required this.storeyId,
    required this.floorZ,
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.lookX,
    required this.lookY,
    required this.clearOfSolids,
  });

  final int storeyId;
  final double floorZ;
  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double lookX;
  final double lookY;
  final bool clearOfSolids;
}

/// Eye and look after `(x, y, z) -> (x, z, -y)`, in local metres.
class ViewerWalk {
  const ViewerWalk({
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.lookX,
    required this.lookY,
    required this.lookZ,
  });

  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double lookX;
  final double lookY;
  final double lookZ;
}

/// Orbit, or one walk pose. [token] changes when the storey pose is replaced.
class WalkCommand {
  const WalkCommand({
    required this.enabled,
    required this.token,
    this.eyeX = 0,
    this.eyeY = 0,
    this.eyeZ = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.lookZ = -1,
  });

  final bool enabled;
  final int token;
  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double lookX;
  final double lookY;
  final double lookZ;

  @override
  bool operator ==(Object other) {
    return other is WalkCommand &&
        other.enabled == enabled &&
        other.token == token &&
        other.eyeX == eyeX &&
        other.eyeY == eyeY &&
        other.eyeZ == eyeZ &&
        other.lookX == lookX &&
        other.lookY == lookY &&
        other.lookZ == lookZ;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, token, eyeX, eyeY, eyeZ, lookX, lookY, lookZ);
}

List<double> localOriginOf(Map<String, dynamic> manifest) {
  final raw = manifest['local_origin'];
  if (raw is! List || raw.length < 3) return const [0, 0, 0];
  return [
    (raw[0] as num?)?.toDouble() ?? 0,
    (raw[1] as num?)?.toDouble() ?? 0,
    (raw[2] as num?)?.toDouble() ?? 0,
  ];
}

ViewerWalk filamentWalk(WalkPose pose, List<double> origin) {
  final ox = origin.isNotEmpty ? origin[0] : 0.0;
  final oy = origin.length > 1 ? origin[1] : 0.0;
  final oz = origin.length > 2 ? origin[2] : 0.0;
  return ViewerWalk(
    eyeX: pose.eyeX - ox,
    eyeY: pose.eyeZ - oz,
    eyeZ: -(pose.eyeY - oy),
    lookX: pose.lookX,
    lookY: 0,
    lookZ: -pose.lookY,
  );
}

/// Storey chosen for a walk: the filter, else the selection, else the first.
SpatialNode? walkStorey({
  required Iterable<SpatialNode> spatial,
  required int? filterStoreyId,
  required int? selectedStoreyId,
}) {
  final storeys = storeysOf(spatial);
  if (filterStoreyId != null) {
    for (final node in storeys) {
      if (node.id == filterStoreyId) return node;
    }
  }
  if (selectedStoreyId != null && selectedStoreyId != 0) {
    for (final node in storeys) {
      if (node.id == selectedStoreyId) return node;
    }
  }
  if (storeys.isEmpty) return null;
  return storeys.first;
}

/// Stand on [elevation] or on the top of the storey's slabs.
///
/// The horizontal start is the footprint centre when that point is
/// [kWalkClearance] outside every non-floor box the eye passes through.
/// Otherwise it is the nearest grid point that is. A footprint with no such
/// point stands at the centre and [WalkPose.clearOfSolids] is false.
/// [anyStorey] uses every box, for a package that has no storey row.
WalkPose walkOnStorey({
  required int storeyId,
  required double elevation,
  required List<ElementBox> boxes,
  bool anyStorey = false,
}) {
  final live = [
    for (final box in boxes)
      if (!box.degenerate && (anyStorey || box.storeyId == storeyId)) box,
  ];
  final floors = [
    for (final box in live)
      if (isWalkFloor(box.ifcClass)) box,
  ];
  final floorZ = floors.isEmpty
      ? elevation
      : floors.map((box) => box.maxZ).reduce(math.max);
  final eyeZ = floorZ + kWalkEyeHeight;
  final span = floors.isNotEmpty ? floors : live;
  if (span.isEmpty) {
    return WalkPose(
      storeyId: storeyId,
      floorZ: elevation,
      eyeX: 0,
      eyeY: 0,
      eyeZ: elevation + kWalkEyeHeight,
      lookX: 0,
      lookY: 1,
      clearOfSolids: true,
    );
  }
  var minX = span.first.minX;
  var maxX = span.first.maxX;
  var minY = span.first.minY;
  var maxY = span.first.maxY;
  for (final box in span.skip(1)) {
    minX = math.min(minX, box.minX);
    maxX = math.max(maxX, box.maxX);
    minY = math.min(minY, box.minY);
    maxY = math.max(maxY, box.maxY);
  }
  final solids = [
    for (final box in live)
      if (!isWalkFloor(box.ifcClass) && box.minZ < eyeZ && box.maxZ > eyeZ) box,
  ];
  final cx = (minX + maxX) / 2;
  final cy = (minY + maxY) / 2;
  final spot = _standOff(cx, cy, minX, maxX, minY, maxY, solids);
  final dx = cx - spot.x;
  final dy = cy - spot.y;
  final len = math.sqrt(dx * dx + dy * dy);
  return WalkPose(
    storeyId: storeyId,
    floorZ: floorZ,
    eyeX: spot.x,
    eyeY: spot.y,
    eyeZ: eyeZ,
    lookX: len < 1e-3 ? 0 : dx / len,
    lookY: len < 1e-3 ? 1 : dy / len,
    clearOfSolids: spot.clear,
  );
}

class _Spot {
  const _Spot(this.x, this.y, this.clear);
  final double x;
  final double y;
  final bool clear;
}

bool _inside(double x, double y, List<ElementBox> solids, double margin) {
  for (final box in solids) {
    if (x < box.minX - margin || x > box.maxX + margin) continue;
    if (y < box.minY - margin || y > box.maxY + margin) continue;
    return true;
  }
  return false;
}

_Spot _standOff(
  double cx,
  double cy,
  double minX,
  double maxX,
  double minY,
  double maxY,
  List<ElementBox> solids,
) {
  if (!_inside(cx, cy, solids, kWalkClearance)) {
    return _Spot(cx, cy, !_inside(cx, cy, solids, 0));
  }
  final wide = _nearestFree(
    cx,
    cy,
    minX,
    maxX,
    minY,
    maxY,
    solids,
    kWalkClearance,
  );
  if (wide != null) return wide;
  final tight = _nearestFree(cx, cy, minX, maxX, minY, maxY, solids, 0);
  if (tight != null) return tight;
  return _Spot(cx, cy, false);
}

_Spot? _nearestFree(
  double cx,
  double cy,
  double minX,
  double maxX,
  double minY,
  double maxY,
  List<ElementBox> solids,
  double margin,
) {
  const steps = 32;
  _Spot? best;
  var bestD = double.infinity;
  for (var i = 0; i <= steps; i++) {
    for (var j = 0; j <= steps; j++) {
      final x = minX + (maxX - minX) * i / steps;
      final y = minY + (maxY - minY) * j / steps;
      if (_inside(x, y, solids, margin)) continue;
      final d = (x - cx) * (x - cx) + (y - cy) * (y - cy);
      if (!_closer(x, y, d, best, bestD)) continue;
      best = _Spot(x, y, true);
      bestD = d;
    }
  }
  return best;
}

bool _closer(double x, double y, double d, _Spot? best, double bestD) {
  if (best == null || d < bestD - 1e-8) return true;
  if ((d - bestD).abs() > 1e-8) return false;
  if (y < best.y - 1e-8) return true;
  if ((y - best.y).abs() > 1e-8) return false;
  return x < best.x - 1e-8;
}
