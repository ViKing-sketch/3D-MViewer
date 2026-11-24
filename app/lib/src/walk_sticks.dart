import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'strings.dart';
import 'walk_stick.dart';

/// Two on-screen sticks. Shown only while a walk is active.
///
/// The layer itself does not take hits: a finger outside either pad still
/// reaches the view under it, so the one-finger look and the two-finger step
/// keep working between the pads.
class WalkStickLayer extends StatefulWidget {
  const WalkStickLayer({
    super.key,
    required this.strings,
    required this.onChanged,
    this.bottom = 12,
  });

  final S strings;
  final ValueChanged<WalkAxes> onChanged;

  /// Distance from the bottom of the layer to the pads.
  final double bottom;

  @override
  State<WalkStickLayer> createState() => _WalkStickLayerState();
}

class _WalkStickLayerState extends State<WalkStickLayer> {
  StickVector _move = StickVector.zero;
  StickVector _look = StickVector.zero;

  void _emit() {
    widget.onChanged(axesFromSticks(move: _move, look: _look));
  }

  @override
  void dispose() {
    if (_move != StickVector.zero || _look != StickVector.zero) {
      widget.onChanged(WalkAxes.zero);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight - _StickPad.diameter - 72;
        final limit = room < 0 ? 0.0 : room;
        final bottom = widget.bottom.clamp(0.0, limit).toDouble();
        return Stack(
          children: [
            Positioned(
              left: 12 + pad.left,
              bottom: bottom,
              child: _StickPad(
                stickKey: const ValueKey('walk-move-stick'),
                label: widget.strings.walkMove,
                icon: Icons.directions_walk,
                onChanged: (raw) {
                  _move = raw;
                  _emit();
                },
              ),
            ),
            Positioned(
              right: 12 + pad.right,
              bottom: bottom,
              child: _StickPad(
                stickKey: const ValueKey('walk-look-stick'),
                label: widget.strings.walkLook,
                icon: Icons.threesixty,
                onChanged: (raw) {
                  _look = raw;
                  _emit();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickPad extends StatefulWidget {
  const _StickPad({
    required this.stickKey,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  static const diameter = 120.0;
  static const knob = 48.0;

  final Key stickKey;
  final String label;
  final IconData icon;
  final ValueChanged<StickVector> onChanged;

  @override
  State<_StickPad> createState() => _StickPadState();
}

class _StickPadState extends State<_StickPad> {
  int? _pointer;
  StickVector _raw = StickVector.zero;

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _place(event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _place(event.localPosition);
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_raw == StickVector.zero) return;
    setState(() => _raw = StickVector.zero);
    widget.onChanged(StickVector.zero);
  }

  void _place(Offset local) {
    const radius = _StickPad.diameter / 2;
    var dx = local.dx - radius;
    var dy = local.dy - radius;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > radius && len > 0) {
      dx = dx / len * radius;
      dy = dy / len * radius;
    }
    final next = StickVector(dx / radius, -dy / radius);
    if (next == _raw) return;
    setState(() => _raw = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = _StickPad.diameter / 2;
    const travel = radius - _StickPad.knob / 2;
    return Semantics(
      container: true,
      label: widget.label,
      child: SizedBox(
        key: widget.stickKey,
        width: _StickPad.diameter,
        height: _StickPad.diameter,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(_StickPad.diameter),
                painter: _StickFace(
                  fill: scheme.surface.withValues(alpha: 0.62),
                  ring: scheme.onSurface.withValues(alpha: 0.28),
                  axis: scheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
              Transform.translate(
                offset: Offset(_raw.x * travel, -_raw.y * travel),
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: 0.94),
                    ),
                    child: SizedBox(
                      width: _StickPad.knob,
                      height: _StickPad.knob,
                      child: Icon(
                        widget.icon,
                        size: 22,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickFace extends CustomPainter {
  const _StickFace({
    required this.fill,
    required this.ring,
    required this.axis,
  });

  final Color fill;
  final Color ring;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius - 1, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius - 1.5,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      center,
      radius * kStickDeadZone,
      Paint()
        ..color = axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final tick = Paint()
      ..color = axis
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const inset = 14.0;
    const gap = 16.0;
    canvas.drawLine(
      Offset(center.dx, inset),
      Offset(center.dx, center.dy - gap),
      tick,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + gap),
      Offset(center.dx, size.height - inset),
      tick,
    );
    canvas.drawLine(
      Offset(inset, center.dy),
      Offset(center.dx - gap, center.dy),
      tick,
    );
    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(size.width - inset, center.dy),
      tick,
    );
  }

  @override
  bool shouldRepaint(_StickFace oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.ring != ring ||
        oldDelegate.axis != axis;
  }
}
