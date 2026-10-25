import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// The 4 OTP digit boxes of canvas `ZOtpA`. Explicitly LTR (the canvas'
/// `direction:ltr` row) even though the page around it is RTL, so digits fill
/// left-to-right in typing order. Driven entirely by [code] (0-4 ASCII
/// digits) — display only; the screen overlays a transparent TextField that
/// supplies the digits from the system keyboard.
///
/// A typed digit sits on a tile with a coloured edge (the wordmark's four
/// colours in turn), the next box to fill has an amber ring and a blinking
/// caret, and the rest are dashed.
class OtpBoxRow extends StatelessWidget {
  final String code;

  /// Draws the active ring and caret (the field has focus and can take input).
  final bool active;

  const OtpBoxRow({super.key, required this.code, this.active = true});

  static const boxCount = 4;
  static const gap = 12.0;
  static const maxWidth = 64.0;
  static const height = 74.0;

  /// Room the boxes' bottom edge (5dp + 3dp outline) needs under them.
  static const edge = 8.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final accents = [z.indigo, z.teal, z.amber, z.coral];
    return Semantics(
      label: 'کد تأیید، ${toPersianDigits(code.length)} رقم از ۴ رقم نوشته شده',
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = ((c.maxWidth - gap * (boxCount - 1)) / boxCount).clamp(
              40.0,
              maxWidth,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: edge),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < boxCount; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: w,
                      height: height,
                      child: _box(context, i, accents[i]),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _box(BuildContext context, int index, Color accent) {
    final z = context.z;
    final zs = context.zs;
    if (index < code.length) {
      return ChunkyBox(
        fill: zs.tile,
        deep: accent,
        depth: ZGame.depthMd,
        radius: 18,
        alignment: Alignment.center,
        child: MediaQuery.withNoTextScaling(
          child: Text(
            toPersianDigits(code[index]),
            style: ZTypography.display.copyWith(
              fontSize: 36,
              height: 1,
              color: z.ink,
            ),
          ),
        ),
      );
    }
    if (index == code.length && active) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: zs.outline, width: ZGame.outline),
          boxShadow: [
            BoxShadow(
              color: zs.outline,
              offset: const Offset(0, ZGame.depthMd),
              spreadRadius: ZGame.outline,
            ),
            BoxShadow(color: z.amber, spreadRadius: ZGame.outline),
          ],
        ),
        child: _Caret(color: z.ink),
      );
    }
    return CustomPaint(
      painter: DashedBorderPainter(
        radius: 18,
        color: zs.chain,
        strokeWidth: ZGame.outline,
        dashWidth: 7,
        dashGap: 5,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The blinking text cursor of the active box (canvas `caret`, a 3×34 bar).
/// Steady under reduced motion.
class _Caret extends StatelessWidget {
  final Color color;

  const _Caret({required this.color});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: 3,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    return ExcludeSemantics(
      child: HomeClock(
        enabled: !homeReducedMotion(context),
        builder:
            (context, ms, child) =>
                Opacity(opacity: (ms % 1000) < 500 ? 1 : 0, child: child),
        child: bar,
      ),
    );
  }
}
