import 'dart:math' as math;

import 'package:field_bim_viewer/src/strings.dart';
import 'package:field_bim_viewer/src/walk_stick.dart';
import 'package:field_bim_viewer/src/walk_sticks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = WalkView(eyeX: 0, eyeY: 1.6, eyeZ: 0, yaw: 0, pitch: 0);

  test('dead zone drops a small deflection and keeps full scale', () {
    expect(stickOutput(0, 0), StickVector.zero);
    expect(stickOutput(0.1, 0), StickVector.zero);
    expect(stickOutput(0, kStickDeadZone), StickVector.zero);
    expect(stickOutput(double.nan, 1), StickVector.zero);

    final full = stickOutput(1, 0);
    expect(full.x, closeTo(1, 1e-9));
    expect(full.y, closeTo(0, 1e-9));
    expect(stickOutput(0, -1).y, closeTo(-1, 1e-9));

    final half = stickOutput(0.5, 0);
    expect(
      half.x,
      closeTo((0.5 - kStickDeadZone) / (1 - kStickDeadZone), 1e-9),
    );
    expect(half.y, 0);

    final mag = math.sqrt(0.3 * 0.3 + 0.4 * 0.4);
    final scaled = (mag - kStickDeadZone) / (1 - kStickDeadZone);
    final angled = stickOutput(0.3, 0.4);
    expect(angled.x, closeTo(0.3 / mag * scaled, 1e-9));
    expect(angled.y, closeTo(0.4 / mag * scaled, 1e-9));

    final diagonal = stickOutput(1, 1);
    final inv = 1 / math.sqrt(2);
    expect(diagonal.x, closeTo(inv, 1e-9));
    expect(diagonal.y, closeTo(inv, 1e-9));
  });

  test('axes follow the left stick for walking and the right for looking', () {
    final held = axesFromSticks(
      move: const StickVector(0, 1),
      look: const StickVector(1, 0),
    );
    expect(held.forward, closeTo(1, 1e-9));
    expect(held.strafe, 0);
    expect(held.yaw, closeTo(1, 1e-9));
    expect(held.pitch, 0);

    final idle = axesFromSticks(
      move: const StickVector(0.1, 0),
      look: const StickVector(0, 0.1),
    );
    expect(idle, WalkAxes.zero);
  });

  test('a level step follows yaw and does not change eye height', () {
    final ahead = stepWalk(origin, const WalkAxes(forward: 1), 1);
    expect(ahead.eyeX, closeTo(0, 1e-6));
    expect(ahead.eyeY, 1.6);
    expect(ahead.eyeZ, closeTo(-kWalkMetresPerSecond, 1e-6));
    expect(ahead.yaw, 0);
    expect(ahead.pitch, 0);

    final side = stepWalk(origin, const WalkAxes(strafe: 1), 1);
    expect(side.eyeX, closeTo(kWalkMetresPerSecond, 1e-6));
    expect(side.eyeY, 1.6);
    expect(side.eyeZ, closeTo(0, 1e-6));

    final turned = stepWalk(
      const WalkView(eyeX: 0, eyeY: 1.6, eyeZ: 0, yaw: math.pi / 2, pitch: 0.4),
      const WalkAxes(forward: 1, strafe: 0.5),
      1,
    );
    expect(turned.eyeX, closeTo(kWalkMetresPerSecond, 1e-6));
    expect(turned.eyeY, 1.6);
    expect(turned.eyeZ, closeTo(0.5 * kWalkMetresPerSecond, 1e-6));
    expect(turned.pitch, closeTo(0.4, 1e-6));
  });

  test('speed stays proportional to the deflection', () {
    final full = stepWalk(origin, const WalkAxes(forward: 1), 0.5);
    final half = stepWalk(origin, const WalkAxes(forward: 0.5), 0.5);
    expect(
      half.eyeZ - origin.eyeZ,
      closeTo((full.eyeZ - origin.eyeZ) / 2, 1e-6),
    );
    expect(half.eyeY, full.eyeY);
  });

  test('pitch is clamped and a look does not move the eye', () {
    final up = stepWalk(origin, const WalkAxes(pitch: 1), 100);
    expect(up.pitch, kWalkMaxPitch);
    expect(up.eyeX, 0);
    expect(up.eyeY, 1.6);
    expect(up.eyeZ, 0);
    expect(up.yaw, 0);

    final down = stepWalk(
      const WalkView(eyeX: 2, eyeY: 1.6, eyeZ: -3, yaw: 0.2, pitch: 0),
      const WalkAxes(pitch: -1, yaw: 1),
      100,
    );
    expect(down.pitch, -kWalkMaxPitch);
    expect(down.yaw, closeTo(0.2 + kWalkYawPerSecond * 100, 1e-4));
    expect(down.eyeX, 2);
    expect(down.eyeY, 1.6);
    expect(down.eyeZ, -3);

    final held = stepWalk(
      const WalkView(eyeX: 1, eyeY: 4, eyeZ: 1, yaw: 0, pitch: kWalkMaxPitch),
      const WalkAxes(pitch: 1),
      1,
    );
    expect(held.pitch, kWalkMaxPitch);
    expect(held.eyeY, 4);
  });

  test('movement uses the yaw from the start of the step', () {
    final next = stepWalk(origin, const WalkAxes(forward: 1, yaw: 1), 1);
    expect(next.eyeZ, closeTo(-kWalkMetresPerSecond, 1e-6));
    expect(next.eyeX, closeTo(0, 1e-6));
    expect(next.eyeY, 1.6);
    expect(next.yaw, closeTo(kWalkYawPerSecond, 1e-6));
    expect(stepWalk(origin, const WalkAxes(forward: 1), 0).eyeZ, 0);
    expect(stepWalk(origin, const WalkAxes(forward: 1), double.nan).eyeZ, 0);
  });

  testWidgets('both sticks report at once and each releases on its own', (
    tester,
  ) async {
    WalkAxes? last;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WalkStickLayer(
            strings: const S(true),
            onChanged: (axes) => last = axes,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('walk-move-stick')), findsOneWidget);
    expect(find.byKey(const ValueKey('walk-look-stick')), findsOneWidget);

    final move = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('walk-move-stick'))),
    );
    final look = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('walk-look-stick'))),
    );
    await move.moveBy(const Offset(0, -48));
    await look.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(last, isNotNull);
    expect(last!.forward, greaterThan(0.4));
    expect(last!.strafe, closeTo(0, 0.08));
    expect(last!.yaw, greaterThan(0.4));
    expect(last!.pitch, closeTo(0, 0.08));

    await move.up();
    await tester.pump();
    expect(last!.forward, 0);
    expect(last!.yaw, greaterThan(0.4));

    await look.up();
    await tester.pump();
    expect(last, WalkAxes.zero);
    expect(tester.takeException(), isNull);
  });
}
