import 'dart:math' as math;

/// Full-stick walk speed, metres per second.
///
/// The same number is applied on Android in `WalkRig.metresPerSecond`.
const double kWalkMetresPerSecond = 2.2;

/// Full-stick turn rates, radians per second. Same values as `WalkRig`.
const double kWalkYawPerSecond = 1.8;
const double kWalkPitchPerSecond = 1.2;

/// Pitch limit, radians. The camera does not flip past this.
///
/// Same value as `WalkRig.maxPitch`.
const double kWalkMaxPitch = 1.15;

/// Radial dead zone as a fraction of a full stick deflection.
const double kStickDeadZone = 0.16;

/// A stick deflection. [x] is right, [y] is up, each nominally in [-1, 1].
class StickVector {
  const StickVector(this.x, this.y);

  static const zero = StickVector(0, 0);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is StickVector && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Axes after the dead zone, each in [-1, 1].
///
/// [strafe] is to the right and [forward] follows the level look. [yaw] turns
/// right. [pitch] looks up. Neither stick changes eye height: the storey
/// chooses that when the walk starts.
class WalkAxes {
  const WalkAxes({
    this.strafe = 0,
    this.forward = 0,
    this.yaw = 0,
    this.pitch = 0,
  });

  static const zero = WalkAxes();

  final double strafe;
  final double forward;
  final double yaw;
  final double pitch;

  @override
  bool operator ==(Object other) {
    return other is WalkAxes &&
        other.strafe == strafe &&
        other.forward == forward &&
        other.yaw == yaw &&
        other.pitch == pitch;
  }

  @override
  int get hashCode => Object.hash(strafe, forward, yaw, pitch);
}

/// Eye in Filament Y-up metres. Yaw 0 looks toward -Z. Pitch 0 is level.
///
/// This is the live walk camera, not a package Z-up pose. A step here does
/// not read a mesh or an element box, so it can pass through a wall.
class WalkView {
  const WalkView({
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.yaw,
    required this.pitch,
  });

  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double yaw;
  final double pitch;
}

/// Radial dead zone. Inside [deadZone] the result is zero. At a full
/// deflection the length is 1, and the direction is unchanged.
StickVector stickOutput(
  double x,
  double y, {
  double deadZone = kStickDeadZone,
}) {
  if (!x.isFinite || !y.isFinite) return StickVector.zero;
  final zone = deadZone.clamp(0.0, 0.99).toDouble();
  var mag = math.sqrt(x * x + y * y);
  if (mag < 1e-8) return StickVector.zero;
  if (mag > 1) {
    x /= mag;
    y /= mag;
    mag = 1;
  }
  if (mag <= zone) return StickVector.zero;
  final scaled = (mag - zone) / (1 - zone) / mag;
  return StickVector(x * scaled, y * scaled);
}

/// Left stick walks, right stick looks. Both values are raw deflections.
WalkAxes axesFromSticks({
  required StickVector move,
  required StickVector look,
}) {
  final step = stickOutput(move.x, move.y);
  final view = stickOutput(look.x, look.y);
  return WalkAxes(strafe: step.x, forward: step.y, yaw: view.x, pitch: view.y);
}

/// One stick step.
///
/// Movement uses the yaw at the start of the step, on the horizontal plane,
/// so pitch does not raise or lower the eye. Look rates are applied after the
/// step and pitch stays inside [kWalkMaxPitch]. [seconds] is the frame time;
/// the Android frame loop already limits that to a tenth of a second.
WalkView stepWalk(WalkView pose, WalkAxes axes, double seconds) {
  if (!seconds.isFinite || seconds <= 0) return pose;
  final forward = _axis(axes.forward) * kWalkMetresPerSecond * seconds;
  final strafe = _axis(axes.strafe) * kWalkMetresPerSecond * seconds;
  final fx = math.sin(pose.yaw);
  final fz = -math.cos(pose.yaw);
  final rx = math.cos(pose.yaw);
  final rz = math.sin(pose.yaw);
  final yaw = pose.yaw + _axis(axes.yaw) * kWalkYawPerSecond * seconds;
  final pitch = (pose.pitch + _axis(axes.pitch) * kWalkPitchPerSecond * seconds)
      .clamp(-kWalkMaxPitch, kWalkMaxPitch);
  return WalkView(
    eyeX: pose.eyeX + fx * forward + rx * strafe,
    eyeY: pose.eyeY,
    eyeZ: pose.eyeZ + fz * forward + rz * strafe,
    yaw: yaw,
    pitch: pitch.toDouble(),
  );
}

double _axis(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(-1.0, 1.0);
}
