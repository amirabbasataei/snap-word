import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/game/view/widgets/z_over_hero.dart';

/// The hero of the pre-game screen (canvas `ZDailyBeforeA`): today's start
/// letter on a big indigo tile hanging from two chain links, swaying, a soft
/// glow behind it, the surprised mascot beside it and the headline under it.
/// Authored on the canvas' 396×330 frame; the mascot moves in on narrow phones
/// so it never sits on the tile. Reduced motion holds the tile still.
class DailyLetterHero extends StatelessWidget {
  final String letter;

  const DailyLetterHero({super.key, required this.letter});

  static const height = 330.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final animate = !homeReducedMotion(context);
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ExcludeSemantics(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [zs.glow, zs.glow, zs.glow.withValues(alpha: 0)],
                      stops: const [0, .45, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: ZOverEnter(
                kind: ZOverEnterKind.up,
                delayMs: 200,
                child: HomeClock(
                  enabled: animate,
                  builder:
                      (context, ms, child) => Transform.rotate(
                        angle: HomeLoop.deg(HomeLoop.swing(ms, 2400, -2, 2)),
                        alignment: Alignment.topCenter,
                        child: child,
                      ),
                  child: _HangingLetter(letter: letter),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            end: narrow ? 8 : 34,
            top: 150,
            child: ZOverEnter(
              kind: ZOverEnterKind.pop,
              delayMs: 500,
              child: ZMascot(
                mood: ZMascotMood.surprised,
                size: narrow ? 72 : 86,
                animate: animate,
              ),
            ),
          ),
          Positioned(
            top: 252,
            left: 0,
            right: 0,
            child: ZOverEnter(
              kind: ZOverEnterKind.up,
              delayMs: 400,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: z.inkSurface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'حرف شروع امروز',
                        style: ZTypography.metaLabel.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: z.onInkSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'تا کجا می‌کشونیش؟',
                          style: ZTypography.display.copyWith(
                            fontSize: 24,
                            height: 1.2,
                            color: z.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Peg, two chain links and the letter tile (canvas: 22 peg, 16×28 links,
/// 128dp tile with an 8dp indigo edge).
class _HangingLetter extends StatelessWidget {
  final String letter;

  const _HangingLetter({required this.letter});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Semantics(
      label: 'حرف شروع امروز: $letter',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: z.surface,
              shape: BoxShape.circle,
              border: Border.all(color: zs.outline, width: ZGame.outline),
            ),
          ),
          _Link(color: zs.chain, outline: zs.outline),
          _Bar(color: zs.chain, outline: zs.outline),
          _Link(color: z.indigo, outline: zs.outline),
          _Bar(color: z.indigo, outline: zs.outline),
          Transform.translate(
            offset: const Offset(0, -6),
            child: ChunkyBox(
              fill: z.indigo,
              deep: z.indigoDeep,
              depth: ZGame.depthXl,
              radius: 30,
              borderWidth: 4,
              width: 128,
              height: 128,
              alignment: Alignment.center,
              child: MediaQuery.withNoTextScaling(
                child: Text(
                  letter,
                  style: ZTypography.display.copyWith(
                    fontSize: 88,
                    height: 1,
                    color: z.onIndigo,
                    shadows: [
                      Shadow(color: z.indigoDeep, offset: const Offset(0, 4)),
                    ],
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

/// A chain ring: 5dp coloured band with a 2.5dp outline on both sides.
class _Link extends StatelessWidget {
  final Color color;
  final Color outline;

  const _Link({required this.color, required this.outline});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -4),
      child: SizedBox(
        width: 16,
        height: 28,
        child: CustomPaint(painter: _RingPainter(color, outline)),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final Color outline;

  const _RingPainter(this.color, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    // The band's centre line is 2.5dp inside the box; the outline is the same
    // path stroked twice as wide.
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width),
    ).deflate(2.5);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = outline,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.outline != outline;
}

/// The short bar between two rings.
class _Bar extends StatelessWidget {
  final Color color;
  final Color outline;

  const _Bar({required this.color, required this.outline});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -8),
      child: Container(
        width: 8,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: outline, spreadRadius: 2.5)],
        ),
      ),
    );
  }
}
