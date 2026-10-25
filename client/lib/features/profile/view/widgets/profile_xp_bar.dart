import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// «۶۲۰ / ۱٬۰۰۰» between the current level's disc and the next one (canvas
/// `ZProfileA`). Real numbers from `GET /profile/stats`: `xp_in_level` and
/// `xp_for_next` (the size of the current level's step).
class ProfileXpBar extends StatelessWidget {
  final int level;
  final int xpInLevel;
  final int xpForNext;

  const ProfileXpBar({
    super.key,
    required this.level,
    required this.xpInLevel,
    required this.xpForNext,
  });

  static double fraction(int inLevel, int forNext) =>
      forNext <= 0 ? 0 : (inLevel / forNext).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final f = fraction(xpInLevel, xpForNext);
    final label =
        '\u2066${formatPersianNumber(xpInLevel)} / '
        '${formatPersianNumber(xpForNext)}\u2069';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        label:
            'سطح ${toPersianDigits(level)}؛ '
            '${formatPersianNumber(xpInLevel)} از '
            '${formatPersianNumber(xpForNext)} امتیاز تا سطح '
            '${toPersianDigits(level + 1)}',
        excludeSemantics: true,
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The bar runs under both discs (canvas: margin 0 -6px).
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 34, end: 28),
                child: Container(
                  height: 22,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: z.wash,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: zs.outline, width: ZGame.outline),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: f,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color.alphaBlend(zs.hi, z.amber),
                                  z.amber,
                                ],
                                stops: const [0, .6],
                              ),
                            ),
                          ),
                        ),
                      ),
                      _BarLabel(
                        text: label,
                        fraction: f,
                        onTrack: z.ink,
                        onFill: z.onAmber,
                      ),
                    ],
                  ),
                ),
              ),
              PositionedDirectional(
                start: 0,
                child: ChunkyBox(
                  fill: z.indigo,
                  depth: ZGame.depthSm,
                  circle: true,
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      toPersianDigits(level),
                      style: ZTypography.button.copyWith(
                        fontSize: 15,
                        color: z.onIndigo,
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: 0,
                child: ChunkyBox(
                  fill: z.surface,
                  depth: 0,
                  circle: true,
                  highlight: false,
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      toPersianDigits(level + 1),
                      style: ZTypography.button.copyWith(
                        fontSize: 14,
                        color: z.ink,
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

/// «۶۲۰ / ۱٬۰۰۰» centred on the bar. The text crosses the edge of the amber
/// fill, and ink (the canvas's choice) is unreadable on amber in dark mode, so
/// it is drawn twice: `onTrack` over the wash, and `onFill` clipped to the
/// filled part.
class _BarLabel extends StatelessWidget {
  final String text;
  final double fraction;
  final Color onTrack;
  final Color onFill;

  const _BarLabel({
    required this.text,
    required this.fraction,
    required this.onTrack,
    required this.onFill,
  });

  @override
  Widget build(BuildContext context) {
    final style = ZTypography.button.copyWith(fontSize: 12, height: 1);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(text, maxLines: 1, style: style.copyWith(color: onTrack)),
        if (fraction > 0)
          Positioned.fill(
            child: ClipRect(
              clipper: _FillClipper(fraction, rtl),
              child: Center(
                child: Text(
                  text,
                  maxLines: 1,
                  style: style.copyWith(color: onFill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FillClipper extends CustomClipper<Rect> {
  final double fraction;
  final bool rtl;

  const _FillClipper(this.fraction, this.rtl);

  @override
  Rect getClip(Size size) {
    final w = size.width * fraction;
    return rtl
        ? Rect.fromLTRB(size.width - w, 0, size.width, size.height)
        : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_FillClipper old) =>
      old.fraction != fraction || old.rtl != rtl;
}
