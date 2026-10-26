import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';

TextStyle _hudText(BuildContext context) => ZTypography.button.copyWith(
  fontSize: 15,
  fontWeight: FontWeight.w900,
  color: context.z.ink,
);

/// Static top bar: level badge with XP ring · coins (+) · streak, then the
/// notifications bell (with its count) and settings at the end.
class HomeHud extends StatelessWidget {
  final int level;

  /// 0..1 progress through the current level.
  final double levelProgress;
  final int coins;
  final int streak;

  /// Invitations waiting in the notifications screen (the bell's badge; none
  /// shown at 0).
  final int messages;
  final VoidCallback onLevelTap;
  final VoidCallback onCoinsTap;
  final VoidCallback onMessagesTap;
  final VoidCallback onSettingsTap;

  const HomeHud({
    super.key,
    required this.level,
    required this.levelProgress,
    required this.coins,
    required this.streak,
    this.messages = 0,
    required this.onLevelTap,
    required this.onCoinsTap,
    required this.onMessagesTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ZGame.hudRowHeight,
      child: Row(
        children: [
          // The cluster only shrinks when the bar cannot fit it next to the
          // two buttons (≤ 360dp wide, or a large system font); on a normal
          // phone it is drawn at its canvas size.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LevelBadge(
                      level: level,
                      progress: levelProgress,
                      onTap: onLevelTap,
                    ),
                    const SizedBox(width: 16),
                    ZHudCoinPill(coins: coins, onTap: onCoinsTap),
                    const SizedBox(width: 10),
                    _StreakPill(streak: streak),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _BellButton(count: messages, onTap: onMessagesTap),
          const SizedBox(width: 10),
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

class _StreakPill extends StatelessWidget {
  final int streak;

  const _StreakPill({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'رکورد روزهای پیاپی ${toPersianDigits(streak)}',
      child: ZChunkPill(
        fill: context.z.surface,
        depth: ZGame.depthSm,
        borderWidth: ZGame.outline,
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
      label: 'حالت شب',
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

/// Opens the notifications screen (canvas `ZHome3A`): a square chunky button
/// with the bell and, while invitations wait, a coral count badge hanging off
/// its end-top corner.
class _BellButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _BellButton({required this.count, required this.onTap});

  /// A badge wider than two digits would crowd the gear.
  static const _maxShown = 99;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      button: true,
      label:
          count > 0 ? 'اعلان‌ها، ${toPersianDigits(count)} مورد' : 'اعلان‌ها',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ChunkyBox(
              fill: z.surface,
              highlight: false,
              depth: ZGame.depthSm,
              radius: 14,
              width: ZGame.hudIconButton,
              height: ZGame.hudIconButton,
              alignment: Alignment.center,
              child: HomeSvg(
                HomeGlyph.bell,
                width: 22,
                height: 22,
                color: z.ink,
              ),
            ),
            if (count > 0)
              PositionedDirectional(
                end: -7,
                top: -7,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: z.coral,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: context.zs.outline, width: 2),
                    ),
                    // Shrink-wrapped, so the pill hugs the number.
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        count > _maxShown
                            ? '${toPersianDigits(_maxShown)}+'
                            : toPersianDigits(count),
                        style: ZTypography.button.copyWith(
                          fontSize: 11,
                          height: 1,
                          color: context.zs.onCoralSm,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
