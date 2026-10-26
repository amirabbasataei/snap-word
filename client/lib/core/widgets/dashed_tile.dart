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

  /// Pulls the stroke inward so it is drawn inside the box like a CSS border
  /// (pass half the stroke width); 0 centres it on the edge.
  final double inset;

  /// Lays the dashes out like a CSS `border-style: dashed`: the pattern starts
  /// on the top edge just after the top-left corner, runs clockwise, and the
  /// gap is stretched so a whole number of periods fits the perimeter.
  final bool cssPhase;

  const DashedBorderPainter({
    required this.radius,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 4.0,
    this.dashGap = 3.0,
    this.inset = 0,
    this.cssPhase = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(inset),
      Radius.circular(radius - inset),
    );
    final path =
        cssPhase ? _clockwiseFromTop(rrect) : (Path()..addRRect(rrect));
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      var gap = dashGap;
      if (cssPhase) {
        final periods = (metric.length / (dashWidth + dashGap)).round();
        if (periods > 0) gap = metric.length / periods - dashWidth;
      }
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        dashPath.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gap;
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

  static Path _clockwiseFromTop(RRect r) {
    final rad = Radius.circular(r.tlRadiusX);
    return Path()
      ..moveTo(r.left + rad.x, r.top)
      ..lineTo(r.right - rad.x, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad.y), radius: rad)
      ..lineTo(r.right, r.bottom - rad.y)
      ..arcToPoint(Offset(r.right - rad.x, r.bottom), radius: rad)
      ..lineTo(r.left + rad.x, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rad.y), radius: rad)
      ..lineTo(r.left, r.top + rad.y)
      ..arcToPoint(Offset(r.left + rad.x, r.top), radius: rad)
      ..close();
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap ||
      oldDelegate.inset != inset ||
      oldDelegate.cssPhase != cssPhase;
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
