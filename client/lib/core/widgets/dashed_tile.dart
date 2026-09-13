import 'package:flutter/material.dart';

/// Dashed rounded-rect border painter — promoted from the game feature's
/// `_DashedRRectPainter` (used by `ZDashedTile`) so other features (e.g. the
/// ZLogin referral teaser card) can reuse the same dashed-border look
/// instead of hand-rolling a new one.
class DashedBorderPainter extends CustomPainter {
  final double radius;
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;

  const DashedBorderPainter({
    required this.radius,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 4.0,
    this.dashGap = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        dashPath.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + dashGap;
      }
    }
    canvas.drawPath(
      dashPath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap;
}

/// A dashed-border rounded rect wrapping arbitrary content — e.g. ZLogin's
/// "کد دعوت داری؟" referral teaser card.
class ZDashedContainer extends StatelessWidget {
  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;

  const ZDashedContainer({
    super.key,
    required this.child,
    required this.color,
    this.radius = 18,
    this.padding = const EdgeInsets.all(13),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DashedBorderPainter(radius: radius, color: color),
      child: Padding(padding: padding, child: child),
    );
  }
}
