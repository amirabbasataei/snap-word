import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/daily/view/widgets/daily_icons.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The three rule tiles under the hero (canvas `ZDailyBeforeA`): lives, the
/// turn timer and the attempts. Every number comes from [GameConstants]; the
/// canvas' «۱۰ ثانیه» and «روزی یک بار» are replaced by what the game really
/// does (15 s per turn; one free attempt, then a paid retry whose better score
/// stays on the board).
class DailyRules extends StatelessWidget {
  const DailyRules({super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final lives = GameConstants.soloLives;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _RuleTile(
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < lives; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      DailyIcons.heart(fill: z.coral, outline: zs.outline),
                    ],
                  ],
                ),
                title: '${toPersianDigits(lives)} جان',
                sub: 'هر اشتباه یکی کم می‌کند',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RuleTile(
                icon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: zs.outline,
                      width: ZGame.outlineInner,
                    ),
                    gradient: SweepGradient(
                      transform: GradientRotation(-math.pi / 2),
                      colors: [z.teal, z.teal, z.wash, z.wash],
                      stops: const [0, .66, .66, 1],
                    ),
                  ),
                ),
                title:
                    '${toPersianDigits(GameConstants.classicTurnTimerSec)} ثانیه',
                sub: 'برای هر نوبت؛ تکرار ممنوع',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RuleTile(
                icon: Container(
                  width: 24,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: z.indigo,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: zs.outline,
                      width: ZGame.outlineInner,
                    ),
                  ),
                  child: Text(
                    toPersianDigits(1),
                    style: ZTypography.button.copyWith(
                      fontSize: 12,
                      height: 1,
                      color: z.onIndigo,
                    ),
                  ),
                ),
                title: 'یک بار رایگان',
                sub:
                    'بار دوم ${toPersianDigits(GameConstants.dailyRetryCostCoins)} سکه',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final Widget icon;
  final String title;
  final String sub;

  const _RuleTile({required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$title، $sub',
      child: ChunkyBox(
        fill: z.surface,
        deep: context.zs.tileDeep,
        depth: 4,
        radius: 18,
        highlight: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 22, child: icon),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ZTypography.button.copyWith(
                fontSize: 15,
                height: 1.2,
                color: z.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: z.ink60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
