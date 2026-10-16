import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';

TextStyle _hudText(BuildContext context) => ZTypography.button.copyWith(
  fontSize: 15,
  fontWeight: FontWeight.w900,
  color: context.z.ink,
);

/// Static top bar: level badge with XP ring · coins (+) · streak · settings.
class HomeHud extends StatelessWidget {
  final int level;

  /// 0..1 progress through the current level.
  final double levelProgress;
  final int coins;
  final int streak;
  final VoidCallback onLevelTap;
  final VoidCallback onCoinsTap;
  final VoidCallback onSettingsTap;

  const HomeHud({
    super.key,
    required this.level,
    required this.levelProgress,
    required this.coins,
    required this.streak,
    required this.onLevelTap,
    required this.onCoinsTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ZGame.hudRowHeight,
      child: Row(
        children: [
          _LevelBadge(level: level, progress: levelProgress, onTap: onLevelTap),
          const SizedBox(width: 16),
          _CoinPill(coins: coins, onTap: onCoinsTap),
          const SizedBox(width: 10),
          _StreakPill(streak: streak),
          const Spacer(),
          _SettingsButton(onTap: onSettingsTap),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final int level;
  final double progress;
  final VoidCallback onTap;

  const _LevelBadge({
    required this.level,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Semantics(
      button: true,
      label: 'سطح ${toPersianDigits(level)}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: ZGame.hudLevel,
          height: ZGame.hudLevel,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: zs.outline, width: ZGame.outline),
            boxShadow: [
              BoxShadow(
                color: zs.outline,
                offset: const Offset(0, ZGame.depthSm),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _XpRingPainter(
              progress: progress.clamp(0, 1).toDouble(),
              fill: z.amber,
              track: z.wash,
            ),
            child: Center(
              child: ChunkyBox(
                fill: z.indigo,
                circle: true,
                depth: 0,
                width: 32,
                height: 32,
                borderWidth: ZGame.outlineInner,
                alignment: Alignment.center,
                child: Text(
                  toPersianDigits(level),
                  textAlign: TextAlign.center,
                  style: ZTypography.button.copyWith(
                    fontSize: 15,
                    height: 1,
                    color: z.onIndigo,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `conic-gradient(amber 0 N%, wash 0)` — starts at 12 o'clock, clockwise.
class _XpRingPainter extends CustomPainter {
  final double progress;
  final Color fill;
  final Color track;

  const _XpRingPainter({
    required this.progress,
    required this.fill,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(rect, Paint()..color = track);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        true,
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_XpRingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}

class _CoinPill extends StatelessWidget {
  final int coins;
  final VoidCallback onTap;

  const _CoinPill({required this.coins, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    // The whole pill is the tap target (44 high); the "+" is its affordance.
    return Semantics(
      button: true,
      label: 'سکه‌ها؛ خرید سکه',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: ZHitTarget.min,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ChunkyBox(
                  fill: z.surface,
                  highlight: false,
                  depth: ZGame.depthSm,
                  radius: 999,
                  height: ZGame.hudPill,
                  // 3 stroke + 4 padding + the coin's 16px of in-flow width.
                  padding: const EdgeInsetsDirectional.only(start: 20, end: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        formatPersianNumber(coins),
                        style: _hudText(context),
                      ),
                      const SizedBox(width: 8),
                      ChunkyBox(
                        fill: z.teal,
                        depth: 0,
                        radius: 8,
                        width: 24,
                        height: 24,
                        borderWidth: 2,
                        highlight: false,
                        alignment: Alignment.center,
                        child: Text(
                          '+',
                          style: ZTypography.button.copyWith(
                            fontSize: 17,
                            height: 1,
                            color: z.onTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The coin overhangs the pill's start edge by 14.
                PositionedDirectional(
                  start: -7,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ChunkyBox(
                      fill: z.amber,
                      circle: true,
                      depth: 0,
                      width: 30,
                      height: 30,
                      borderWidth: ZGame.outlineInner,
                      alignment: Alignment.center,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: z.amberDeep, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  final int streak;

  const _StreakPill({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'رکورد روزهای پیاپی ${toPersianDigits(streak)}',
      child: ChunkyBox(
        fill: context.z.surface,
        highlight: false,
        depth: ZGame.depthSm,
        radius: 999,
        height: ZGame.hudPill,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HomeSvg(HomeGlyph.flame, width: 20, height: 24),
            const SizedBox(width: 5),
            Text(toPersianDigits(streak), style: _hudText(context)),
          ],
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'تنظیمات',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ChunkyBox(
          fill: context.z.surface,
          highlight: false,
          depth: ZGame.depthSm,
          radius: 14,
          width: ZGame.hudIconButton,
          height: ZGame.hudIconButton,
          alignment: Alignment.center,
          child: HomeSvg(
            HomeGlyph.gear,
            width: 22,
            height: 22,
            color: context.z.ink,
          ),
        ),
      ),
    );
  }
}
