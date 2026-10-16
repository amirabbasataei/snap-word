import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_buttons.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';

/// The chunky HUD pieces of the "A · mascot-led" game screens (canvas turn 7,
/// `ZSoloA`): back button, score pill, countdown ring, lives and words chips.
/// Built on [ChunkyBox] / [ChunkyPressable] so ZPlay / ZOver can reuse them.

/// 44dp back button: surface square, 3px outline, 3px solid edge.
class ZGameBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticLabel;

  const ZGameBackButton({
    super.key,
    required this.onTap,
    this.semanticLabel = 'بازگشت',
  });

  @override
  Widget build(BuildContext context) {
    final ink = svgHex(context.z.ink);
    return ChunkyPressable(
      depth: ZGame.depthSm,
      onTap: onTap,
      semanticLabel: semanticLabel,
      builder:
          (context, depth, _) => ChunkyBox(
            fill: context.z.surface,
            depth: depth,
            radius: 14,
            highlight: false,
            width: ZGame.gameBackButton,
            height: ZGame.gameBackButton,
            alignment: Alignment.center,
            child: SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
              width: 20,
              height: 20,
            ),
          ),
    );
  }
}

/// Score on one side, mode title + subtitle on the other, split by a rule.
class ZScorePill extends StatelessWidget {
  final int score;
  final String title;
  final String subtitle;

  /// Narrow phones: drop the subtitle and scale the pill down to fit.
  final bool compact;

  const ZScorePill({
    super.key,
    required this.score,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final pill = ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthMd - 1,
      radius: 16,
      highlight: false,
      height: ZGame.gameScorePillHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                toPersianDigits(score),
                style: TextStyle(
                  color: z.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  height: 1,
                ),
              ),
              Text(
                'امتیاز',
                style: TextStyle(
                  color: z.ink60,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 28,
            decoration: BoxDecoration(
              color: zs.track,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: z.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  height: 1.1,
                ),
              ),
              if (!compact)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: z.ink60,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return FittedBox(fit: BoxFit.scaleDown, child: pill);
  }
}

/// Circular turn timer: a coral wedge for the time left on a `wash` disc, the
/// remaining seconds in a surface core. Pulses (canvas `urgent`) once
/// [urgentAt] seconds or fewer remain, unless motion is reduced.
class ZTimerRing extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  final int urgentAt;

  const ZTimerRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    this.urgentAt = 5,
  });

  /// Canvas `urgent`: a 1 → 1.12 → 1 beat per second.
  static double pulseScale(double ms) => HomeLoop.keyframes(ms, 1000, const [
    (0, 1),
    (.15, 1.12),
    (.35, 1),
    (1, 1),
  ]);

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final fraction =
        totalSeconds <= 0
            ? 0.0
            : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final urgent = secondsRemaining <= urgentAt && !homeReducedMotion(context);

    Widget ring(double scale) => Transform.scale(
      scale: scale,
      child: ChunkyBox(
        fill: z.wash,
        depth: ZGame.depthMd - 1,
        circle: true,
        highlight: false,
        width: ZGame.gameTimerRing,
        height: ZGame.gameTimerRing,
        child: CustomPaint(
          painter: _WedgePainter(fraction: fraction, color: z.coral),
          child: Center(
            child: Container(
              width: ZGame.gameTimerCore,
              height: ZGame.gameTimerCore,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: z.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: zs.outline,
                  width: ZGame.outlineInner,
                ),
              ),
              child: Text(
                toPersianDigits(secondsRemaining.toString().padLeft(2, '0')),
                style: TextStyle(
                  color: zs.coralInk,
                  fontWeight: FontWeight.w900,
                  fontSize: 21,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      label: '${toPersianDigits(secondsRemaining)} ثانیه',
      excludeSemantics: true,
      child:
          urgent
              ? HomeClock(
                enabled: true,
                builder: (context, ms, _) => ring(pulseScale(ms)),
              )
              : ring(1),
    );
  }
}

class _WedgePainter extends CustomPainter {
  final double fraction;
  final Color color;

  const _WedgePainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (fraction <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      true,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_WedgePainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Hearts for the lives left; spent lives are drawn as empty `wash` hearts
/// (the canvas only shows the full state).
class ZLivesChip extends StatelessWidget {
  final int lives;
  final int maxLives;

  const ZLivesChip({super.key, required this.lives, required this.maxLives});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final o = svgHex(context.zs.outline);
    String heart(Color fill) =>
        '<svg viewBox="0 0 24 22"><path d="M12 20S2 14 2 7.5A5 5 0 0 1 12 5a5 5 0 0 1 10 2.5C22 14 12 20 12 20z" fill="${svgHex(fill)}" stroke="$o" stroke-width="2.4" stroke-linejoin="round"/></svg>';
    return Semantics(
      label: '${toPersianDigits(lives)} جان',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: z.surface,
        depth: ZGame.depthSm,
        radius: 999,
        highlight: false,
        height: ZGame.gameChipHeight,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < maxLives; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              SvgPicture.string(
                heart(i < lives ? z.coral : z.wash),
                width: ZGame.gameHeartWidth,
                height: ZGame.gameHeartHeight,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «۹ کلمه  رکورد ۲۳» — words in this chain and the player's longest chain.
class ZWordsChip extends StatelessWidget {
  final int words;
  final int record;

  const ZWordsChip({super.key, required this.words, required this.record});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthSm,
      radius: 999,
      highlight: false,
      height: ZGame.gameChipHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${toPersianDigits(words)} کلمه',
            style: TextStyle(
              color: z.ink,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'رکورد ${toPersianDigits(record)}',
            style: TextStyle(
              color: z.ink60,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
