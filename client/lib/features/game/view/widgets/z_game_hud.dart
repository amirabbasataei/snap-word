import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pill.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// The chunky HUD pieces of the "A · mascot-led" game screens (canvas turn 7,
/// `ZSoloA`): back button, score pill, countdown ring, lives and words chips.
/// Built on [ChunkyBox] / [ChunkyPressable] so ZPlay / ZOver can reuse them.

/// 44dp back button: surface square, 3px outline, 3px solid edge. [close]
/// swaps the arrow for the ✕ of the result screen (canvas `ZOverA`).
class ZGameBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticLabel;
  final bool close;

  const ZGameBackButton({
    super.key,
    required this.onTap,
    this.semanticLabel = 'بازگشت',
    this.close = false,
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
              close
                  ? '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3.4" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>'
                  : '<svg viewBox="0 0 24 24" fill="none" stroke="$ink" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
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
///
/// With [calm] (ZPlay) the wedge is teal and the number plain ink until the
/// urgent window, when it switches to the coral of the solo ring. [paused]
/// dims the ring (the AI's turn: the clock is not running).
class ZTimerRing extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  final int urgentAt;
  final bool calm;
  final bool paused;

  const ZTimerRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    this.urgentAt = 5,
    this.calm = false,
    this.paused = false,
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
    final inUrgentWindow = secondsRemaining <= urgentAt && !paused;
    final urgent = inUrgentWindow && !homeReducedMotion(context);
    final wedge = calm && !inUrgentWindow ? z.teal : z.coral;
    final numberColor = calm && !inUrgentWindow ? z.ink : zs.coralInk;

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
          painter: _WedgePainter(fraction: fraction, color: wedge),
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
                  color: numberColor,
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

    final face =
        urgent
            ? HomeClock(
              enabled: true,
              builder: (context, ms, _) => ring(pulseScale(ms)),
            )
            : ring(1);
    return Semantics(
      label: '${toPersianDigits(secondsRemaining)} ثانیه',
      excludeSemantics: true,
      // Wrapped only while paused: an Opacity(1) layer changes edge pixels.
      child: paused ? Opacity(opacity: .55, child: ring(1)) : face,
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
      child: ZChunkPill(
        fill: z.surface,
        depth: ZGame.depthSm,
        borderWidth: ZGame.outline,
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
    return ZChunkPill(
      fill: z.surface,
      depth: ZGame.depthSm,
      borderWidth: ZGame.outline,
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

/// Head-to-head score pill of ZPlay (canvas `ZPlayA`): your disc and score on
/// the start side, the opponent's on the end side, and a chip in the middle
/// saying whose turn it is.
///
/// The canvas is drawn at 396dp; on narrower phones the pill measures its
/// content and steps down — full discs, then small ones, then none — so the
/// turn chip is never squeezed below legibility. The step depends on the
/// longer of the two turn labels and the current scores, not on whose turn it
/// is, so the layout doesn't jump when the turn changes.
class ZVersusPill extends StatelessWidget {
  /// Builds a disc of the given size (so the pill can pick the size).
  final Widget Function(double size) myAvatar;
  final String myLabel;
  final int myScore;
  final Widget Function(double size) opponentAvatar;
  final String opponentLabel;
  final int opponentScore;
  final bool myTurn;
  final String myTurnLabel;
  final String opponentTurnLabel;

  const ZVersusPill({
    super.key,
    required this.myAvatar,
    required this.myLabel,
    required this.myScore,
    required this.opponentAvatar,
    required this.opponentLabel,
    required this.opponentScore,
    required this.myTurn,
    required this.myTurnLabel,
    required this.opponentTurnLabel,
  });

  static const _maxSide = 64.0;
  static const _chipPad = 8.0;
  static const _scoreStyle = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 20,
    height: 1,
  );
  static const _labelStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 12,
    height: 1.3,
  );
  static const _chipStyle = TextStyle(
    fontWeight: FontWeight.w900,
    fontSize: 12,
    height: 1,
  );

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      // Inherit the theme font (Vazirmatn) so the measure matches the render.
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  double _sideWidth(BuildContext context, int score, String label) =>
      math
          .max(
            _textWidth(context, toPersianDigits(score), _scoreStyle),
            _textWidth(context, label, _labelStyle),
          )
          .clamp(0, _maxSide)
          .toDouble();

  Widget _side(
    BuildContext context,
    int score,
    String label,
    CrossAxisAlignment align,
  ) {
    final z = context.z;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: align,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxSide),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              toPersianDigits(score),
              style: _scoreStyle.copyWith(color: z.ink),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxSide),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _labelStyle.copyWith(color: z.ink),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final turnLabel = myTurn ? myTurnLabel : opponentTurnLabel;
    final chip = Container(
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: _chipPad),
      decoration: BoxDecoration(
        color: myTurn ? z.inkSurface : z.wash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        turnLabel,
        maxLines: 1,
        softWrap: false,
        style: _chipStyle.copyWith(color: myTurn ? z.onInkSurface : z.ink),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        // padding 2×8 + outline 2×3, then the sides and the widest chip.
        final base =
            22 +
            _sideWidth(context, myScore, myLabel) +
            _sideWidth(context, opponentScore, opponentLabel) +
            math.max(
              _textWidth(context, myTurnLabel, _chipStyle),
              _textWidth(context, opponentTurnLabel, _chipStyle),
            ) +
            2 * _chipPad +
            4;
        // Avatar + its 8dp gap, on both sides.
        final discSize =
            base + 2 * (ZGame.gameDisc + 8) <= c.maxWidth
                ? ZGame.gameDisc
                : base + 2 * (ZGame.gameDiscSmall + 6) <= c.maxWidth
                ? ZGame.gameDiscSmall
                : null;
        final gap = discSize == ZGame.gameDisc ? 8.0 : 6.0;
        return ChunkyBox(
          fill: z.surface,
          depth: ZGame.depthMd - 1,
          radius: 18,
          highlight: false,
          height: ZGame.gameVersusPillHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (discSize != null) ...[
                myAvatar(discSize),
                SizedBox(width: gap),
              ],
              _side(context, myScore, myLabel, CrossAxisAlignment.start),
              Expanded(
                child: Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: chip),
                ),
              ),
              _side(
                context,
                opponentScore,
                opponentLabel,
                CrossAxisAlignment.end,
              ),
              if (discSize != null) ...[
                SizedBox(width: gap),
                opponentAvatar(discSize),
              ],
            ],
          ),
        );
      },
    );
  }
}
