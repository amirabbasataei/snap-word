import 'dart:math' as math;

import 'package:flutter/material.dart';

/// `repeating-conic-gradient(rays 0 10deg, transparent 10deg 24deg)` masked by
/// a radial fade (opaque to 25%, gone by 70% of the corner distance).
class ZRaysPainter extends CustomPainter {
  final Color color;

  const ZRaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * math.sqrt2;
    final path = Path();
    for (var a = -90.0; a < 270; a += 24) {
      path
        ..moveTo(c.dx, c.dy)
        ..arcTo(
          Rect.fromCircle(center: c, radius: r),
          a * math.pi / 180,
          10 * math.pi / 180,
          false,
        )
        ..close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color, color.withValues(alpha: 0)],
          stops: const [0, .25, .70],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(ZRaysPainter old) => old.color != color;
}
