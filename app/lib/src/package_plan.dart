import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'model.dart';

/// Plan of element boxes for the library list.
///
/// The rectangles are `elements.bbox_*` in world metres, drawn from above.
/// format_version 1 does not store `thumbs/`, and this is not a render of the mesh.
class PackagePlan extends StatelessWidget {
  const PackagePlan({super.key, required this.boxes});

  final List<PlanBox> boxes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: CustomPaint(
        painter: PackagePlanPainter(
          boxes,
          outline: Theme.of(context).colorScheme.outline,
          empty: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

class PackagePlanPainter extends CustomPainter {
  PackagePlanPainter(this.boxes, {required this.outline, required this.empty});

  final List<PlanBox> boxes;
  final Color outline;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = empty;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      background,
    );
    if (boxes.isEmpty || size.width < 2 || size.height < 2) return;
    var minX = boxes.first.minX;
    var maxX = boxes.first.maxX;
    var minY = boxes.first.minY;
    var maxY = boxes.first.maxY;
    for (final box in boxes.skip(1)) {
      minX = math.min(minX, box.minX);
      maxX = math.max(maxX, box.maxX);
      minY = math.min(minY, box.minY);
      maxY = math.max(maxY, box.maxY);
    }
    final spanX = math.max(maxX - minX, 1e-6);
    final spanY = math.max(maxY - minY, 1e-6);
    const pad = 4.0;
    final innerW = size.width - pad * 2;
    final innerH = size.height - pad * 2;
    final scale = math.min(innerW / spanX, innerH / spanY);
    final usedW = spanX * scale;
    final usedH = spanY * scale;
    final ox = pad + (innerW - usedW) / 2;
    final oy = pad + (innerH - usedH) / 2;
    for (final box in boxes) {
      final left = ox + (box.minX - minX) * scale;
      final right = ox + (box.maxX - minX) * scale;
      final top = oy + (maxY - box.maxY) * scale;
      final bottom = oy + (maxY - box.minY) * scale;
      final paint = Paint()
        ..color = Color.from(
          alpha: 1,
          red: box.red,
          green: box.green,
          blue: box.blue,
        );
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(PackagePlanPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}
