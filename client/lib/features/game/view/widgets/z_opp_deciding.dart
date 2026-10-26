import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_form_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// Canvas `ZOppDeciding` (15a): the 1v1 overlay shown while the opponent
/// decides whether to continue after losing. Scrim + the dialog card, driven
/// by the real continue window ([remaining] of
/// [GameConstants.continueWindowSec] seconds, ticked by `GameBloc`).
class ZOppDecidingOverlay extends StatelessWidget {
  final int remaining;

  /// Why the opponent lost (`invalid_word` | `timeout`); null → rejected word.
  final String? lossReason;

  const ZOppDecidingOverlay({
    super.key,
    required this.remaining,
    this.lossReason,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(color: context.zs.scrim, dismissible: false),
          Center(
            child: Padding(
              // The card's solid edge is reserved below it (ZDialogCard); the
              // canvas centres the card without it, so mirror it above.
              padding: const EdgeInsets.fromLTRB(
                ZGame.dialogInset,
                ZGame.dialogDepth,
                ZGame.dialogInset,
                0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ZGame.dialogMaxWidth,
                ),
                child: ZDropIn(
                  child: ZOppDecidingCard(
                    remaining: remaining,
                    lossReason: lossReason,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dialog card of [ZOppDecidingOverlay] without the scrim.
class ZOppDecidingCard extends StatelessWidget {
  final int remaining;
  final String? lossReason;

  const ZOppDecidingCard({super.key, required this.remaining, this.lossReason});

  /// The ring and the number turn coral for the last seconds.
  static const lateSeconds = 3;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final left = remaining.clamp(0, GameConstants.continueWindowSec);
    final timeout = lossReason == 'timeout';
    return ZDialogCard(
      semanticLabel: 'حریف داره تصمیم می‌گیره',
      mascot: const ZMascot(
        mood: ZMascotMood.thinking,
        size: ZGame.dialogMascotSize,
        shadow: false,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _StatusPill()),
            const SizedBox(height: 14),
            Center(
              child: _CountdownRing(
                left: left,
                total: GameConstants.continueWindowSec,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'حریف داره تصمیم می‌گیره…',
              textAlign: TextAlign.center,
              style: ZTypography.screenTitle.copyWith(
                fontSize: 22,
                height: 1.3,
                color: z.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              timeout
                  ? 'وقت حریف تموم شد. یه فرصت دیگه داره که بازی رو ادامه بده.'
                  : 'کلمهٔ حریف رد شد. یه فرصت دیگه داره که بازی رو ادامه بده.',
              textAlign: TextAlign.center,
              style: ZTypography.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.65,
                color: z.ink60,
              ),
            ),
            const SizedBox(height: 14),
            const _CostPanel(),
            const SizedBox(height: 14),
            const _WinNote(),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.inkSurface,
      depth: 0,
      radius: 999,
      borderWidth: ZGame.outlineInner,
      highlight: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // A Row, not `alignment:` — an aligned box would stretch to the card.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: z.amber),
          const SizedBox(width: 6),
          Text(
            'نوبت حریف · بازی متوقف شد',
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1,
              color: z.onInkSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 8px status dot with the canvas `pulse` loop (1 → 1.035 → 1, 2.2 s).
class _PulseDot extends StatelessWidget {
  final Color color;

  const _PulseDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return HomeClock(
      enabled: !homeReducedMotion(context),
      builder:
          (context, ms, child) => Transform.scale(
            scale: HomeLoop.keyframes(ms, 2200, const [
              (0, 1),
              (.2, 1.035),
              (.4, 1),
              (1, 1),
            ], delayMs: 800),
            child: child,
          ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// The 124dp countdown ring: a wash disc in a 16dp outline, a 9dp track and a
/// round-capped progress arc that drains clockwise from the top. The arc
/// slides to each new value over 1 s (the bloc ticks once a second).
class _CountdownRing extends StatelessWidget {
  final int left;
  final int total;

  static const size = 124.0;

  const _CountdownRing({required this.left, required this.total});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final late = left <= ZOppDecidingCard.lateSeconds;
    final arc = late ? z.coral : z.amber;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: left / total),
            duration: const Duration(seconds: 1),
            builder:
                (context, progress, _) => TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: arc),
                  duration: const Duration(milliseconds: 300),
                  builder:
                      (context, color, _) => CustomPaint(
                        size: const Size.square(size),
                        painter: _RingPainter(
                          progress: progress,
                          fill: z.wash,
                          outline: zs.outline,
                          track: zs.track,
                          arc: color ?? arc,
                        ),
                      ),
                ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                toPersianDigits(left),
                style: ZTypography.display.copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: late ? zs.coralInk : z.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ثانیه',
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: z.ink60,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color fill;
  final Color outline;
  final Color track;
  final Color arc;

  const _RingPainter({
    required this.progress,
    required this.fill,
    required this.outline,
    required this.track,
    required this.arc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 50.0;
    canvas.drawCircle(c, r, Paint()..color = fill);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = arc
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.outline != outline ||
      old.track != track ||
      old.arc != arc;
}

/// What the opponent would pay to continue. The canvas draws 20 coins; the
/// real price is [GameConstants.continueCostCoins].
class _CostPanel extends StatelessWidget {
  const _CostPanel();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'حریف می‌تونه با خرج سکه ادامه بده',
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.5,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 6),
          ZRewardChip(
            amount: '${toPersianDigits(GameConstants.continueCostCoins)} سکه',
            caption: 'خرج از کیف',
            dot: z.amber,
          ),
        ],
      ),
    );
  }
}

/// The dashed teal line telling the player what the timeout means for them.
class _WinNote extends StatelessWidget {
  const _WinNote();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return CustomPaint(
      painter: DashedBorderPainter(
        radius: 16,
        color: z.teal,
        strokeWidth: ZGame.outlineInner,
        // CSS `dashed`: a dash is 2× the stroke, a gap 1× (≥3 device px).
        dashWidth: 2 * ZGame.outlineInner,
        dashGap: ZGame.outlineInner,
        inset: ZGame.outlineInner / 2,
        cssPhase: true,
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChunkyBox(
              fill: z.teal,
              depth: 0,
              circle: true,
              borderWidth: 2,
              highlight: false,
              // `width:10px` plus a 2px border, no border-box: 14 outer.
              width: 14,
              height: 14,
            ),
            const SizedBox(width: 8),
            Text(
              'اگه تا آخر زمان ادامه نده، تو می‌بری',
              style: ZTypography.metaLabel.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                height: 1.2,
                color: zs.tealInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
