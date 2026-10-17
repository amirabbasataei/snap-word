import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// «زنجیر» lockup — four-colour wordmark with a chunky stroke (no drop
/// shadow), plus the tagline pill. Static.
class HomeLogo extends StatelessWidget {
  const HomeLogo({super.key});

  // Canvas: ز indigo · ن teal · ج amber · ی coral · ر indigo.
  static const _letters = ['ز', 'ن', 'ج', 'ی', 'ر'];
  static const tagline = 'حرف آخر، حرف اول!';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final colors = [z.indigo, z.teal, z.amber, z.coral, z.indigo];

    TextSpan spans(Paint? stroke, Color? solid) => TextSpan(
      children: [
        for (var i = 0; i < _letters.length; i++)
          TextSpan(
            text: _letters[i],
            style:
                stroke != null
                    ? TextStyle(foreground: stroke)
                    : TextStyle(color: solid ?? colors[i]),
          ),
      ],
    );

    final base = ZTypography.display.copyWith(
      fontSize: ZGame.logoSize,
      height: 1.05,
      letterSpacing: ZTypography.wordmarkLetterSpacing,
    );
    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = ZGame.logoStroke
          ..color = zs.outline;

    Widget layer(TextSpan span) => Text.rich(
      span,
      style: base,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'زنجیر',
          excludeSemantics: true,
          child: Stack(
            alignment: Alignment.center,
            children: [
              layer(spans(strokePaint, null)),
              layer(spans(null, null)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Transform.rotate(
          angle: HomeLoop.deg(-2),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
            decoration: BoxDecoration(
              color: z.inkSurface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(color: z.coral, offset: const Offset(0, 3)),
              ],
            ),
            child: Text(
              tagline,
              style: ZTypography.button.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
                color: z.onInkSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
