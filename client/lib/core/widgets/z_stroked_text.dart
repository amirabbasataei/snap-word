import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// Big sticker-style title (canvas `-webkit-text-stroke: Npx outline;
/// paint-order: stroke fill`): [fill] letters with a round-joined outline
/// stroke. No drop shadow — stroke plus shadow clogged the Persian letter
/// counters. The result titles of ZOver use it; the home wordmark draws the
/// same recipe by hand because it is four colours.
///
/// Scales down (never wraps) when [text] is wider than the space it is given.
class ZStrokedText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color fill;
  final double stroke;

  const ZStrokedText(
    this.text, {
    super.key,
    required this.fontSize,
    required this.fill,
    required this.stroke,
  });

  @override
  Widget build(BuildContext context) {
    final outline = context.zs.outline;
    final base = ZTypography.display.copyWith(fontSize: fontSize, height: 1.15);
    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = stroke
          ..color = outline;

    // Decorative layers are RichText so only the top fill is a `Text`
    // (one text node for tests and for the semantics tree).
    Widget layer(TextStyle style) => RichText(
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      text: TextSpan(text: text, style: style),
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        // Room for the stroke so FittedBox doesn't clip it.
        padding: EdgeInsets.symmetric(horizontal: stroke, vertical: stroke / 2),
        child: Stack(
          alignment: Alignment.center,
          children: [
            layer(base.copyWith(foreground: strokePaint)),
            Text(
              text,
              textAlign: TextAlign.center,
              style: base.copyWith(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}
