import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_rays.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';

/// The result hero (canvas `ZDailyAfterA`): slowly turning rays, an amber disc
/// with the chain length, the happy mascot beside it and the player's rank on
/// a dark pill. The canvas' «بهتر از ۷۸٪ بازیکن‌ها» and «از ۸٬۲۳۰» need a
/// player count the server does not send (todo.md 2.5), so the pill states the
/// rank alone and the score sits in a chip under it.
class DailyResultHero extends StatelessWidget {
  final int words;
  final int score;

  /// Null when the server has no rank for the player.
  final int? rank;

  const DailyResultHero({
    super.key,
    required this.words,
    required this.score,
    required this.rank,
  });

  static const stage = 236.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final animate = !homeReducedMotion(context);
    final rankText =
        rank != null
            ? 'رتبهٔ ${toPersianDigits(rank!)} امروز'
            : 'نتیجهٔ امروزت ثبت شد';
    return Column(
      children: [
        SizedBox(
          height: stage,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 0,
                child: ExcludeSemantics(
                  child: HomeClock(
                    enabled: animate,
                    builder:
                        (context, ms, child) => Transform.rotate(
                          angle: ms / 24000 * 6.283185307179586,
                          child: child,
                        ),
                    child: CustomPaint(
                      size: const Size(240, 240),
                      painter: ZRaysPainter(zs.rays),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 30,
                child: ZOverEnter(
                  kind: ZOverEnterKind.pop,
                  delayMs: 200,
                  child: Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: '${toPersianDigits(words)} کلمه',
                    child: ChunkyBox(
                      fill: z.amber,
                      deep: z.amberDeep,
                      depth: ZGame.depthXl,
                      circle: true,
                      borderWidth: 4,
                      width: 150,
                      height: 150,
                      alignment: Alignment.center,
                      child: ChunkyBox(
                        fill: z.surface,
                        depth: 0,
                        circle: true,
                        highlight: false,
                        width: 116,
                        height: 116,
                        alignment: Alignment.center,
                        child: MediaQuery.withNoTextScaling(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 90,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    toPersianDigits(words),
                                    style: ZTypography.display.copyWith(
                                      fontSize: 56,
                                      height: 1,
                                      color: z.ink,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                'کلمه',
                                style: ZTypography.button.copyWith(
                                  fontSize: 14,
                                  height: 1.2,
                                  color: z.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                end: narrow ? 6 : 22,
                top: 92,
                child: ZOverEnter(
                  kind: ZOverEnterKind.pop,
                  delayMs: 450,
                  child: ZMascot(
                    mood: ZMascotMood.happy,
                    size: narrow ? 72 : 86,
                    animate: animate,
                  ),
                ),
              ),
              Positioned(
                top: 196,
                left: 16,
                right: 16,
                child: ZOverEnter(
                  kind: ZOverEnterKind.up,
                  delayMs: 500,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: z.inkSurface,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: z.teal,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            rankText,
                            maxLines: 1,
                            style: ZTypography.button.copyWith(
                              fontSize: 14,
                              height: 1,
                              color: z.onInkSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ZOverEnter(
          kind: ZOverEnterKind.up,
          delayMs: 550,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: z.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: zs.outline,
                      width: ZGame.outlineInner,
                    ),
                  ),
                  child: Text(
                    '${formatPersianNumber(score)} امتیاز',
                    maxLines: 1,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: z.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
