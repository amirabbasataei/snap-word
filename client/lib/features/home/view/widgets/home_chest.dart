import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// Reward chest. When [ready] (there are unclaimed rewards) it glows, throws
/// spinning rays, wiggles, and shows the «جایزه آماده!» tag and a red dot;
/// otherwise it sits calm. Tapping opens the rewards inbox.
class HomeChest extends StatelessWidget {
  final bool ready;
  final bool animate;
  final VoidCallback onTap;

  const HomeChest({
    super.key,
    required this.ready,
    required this.onTap,
    this.animate = true,
  });

  static const size = Size(150, 150);
  static const readyLabel = 'جایزه آماده!';

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: HomeClock(
        enabled: animate && ready,
        builder: (context, ms, _) => _content(context, ms),
      ),
    );
  }

  Widget _content(BuildContext context, double ms) {
    final z = context.z;
    final zs = context.zs;
    final glow = HomeLoop.pingPong(ms, ZGameMotion.glow);
    final wiggle = ready ? HomeLoop.wiggle(ms) : 0.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (ready) ...[
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: .8 + .2 * glow,
                child: Transform.scale(
                  scale: .92 + .16 * glow,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        // farthest-corner of a 150 box = 106 → 0.707 of side.
                        radius: .707,
                        colors: [
                          zs.glow,
                          zs.glow,
                          zs.glow.withValues(alpha: 0),
                        ],
                        stops: const [0, .32, .68],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 5,
            top: 5,
            width: 140,
            height: 140,
            child: IgnorePointer(
              child: Transform.rotate(
                angle:
                    2 * math.pi * ((ms % ZGameMotion.spin) / ZGameMotion.spin),
                child: CustomPaint(painter: _RaysPainter(zs.rays)),
              ),
            ),
          ),
          Positioned(
            left: 28,
            top: 30,
            width: 12,
            height: 12,
            child: _twinkle(ms, 200, z.amber),
          ),
          Positioned(
            left: 112,
            top: 40,
            width: 10,
            height: 10,
            child: _twinkle(ms, 900, z.surface),
          ),
        ],
        Positioned(
          left: 37,
          top: 46,
          width: 76,
          height: 64,
          child: Semantics(
            button: true,
            label: ready ? readyLabel : 'جایزه‌ها',
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Transform.rotate(
                angle: HomeLoop.deg(wiggle),
                alignment: Alignment.bottomCenter,
                child: _ChestBody(showDot: ready),
              ),
            ),
          ),
        ),
        if (ready)
          Positioned(
            left: 37,
            top: 120,
            width: 76,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                height: 24,
                decoration: BoxDecoration(
                  color: z.coral,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: zs.outline, width: 2.5),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    readyLabel,
                    style: ZTypography.button.copyWith(
                      fontSize: 12,
                      height: 1,
                      color: z.onCoral,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _twinkle(double ms, int delay, Color color) {
    final k = HomeLoop.twinkle(ms, delayMs: delay);
    return Opacity(
      opacity: .3 + .7 * k,
      child: Transform.scale(
        scale: .4 + .6 * k,
        child: CustomPaint(painter: SparklePainter(color)),
      ),
    );
  }
}

class _ChestBody extends StatelessWidget {
  final bool showDot;

  const _ChestBody({required this.showDot});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Lid.
        Positioned(
          left: 0,
          top: 0,
          child: ChunkyBox(
            fill: z.teal,
            depth: 0,
            width: 76,
            height: 26,
            radius: 14,
          ),
        ),
        // Base with its solid edge.
        Positioned(
          left: 4,
          top: 23,
          child: ChunkyBox(
            fill: z.teal,
            deep: z.tealDeep,
            depth: ZGame.depthMd,
            highlight: false,
            width: 68,
            height: 38,
            radius: 4,
          ),
        ),
        // Strap and latch.
        Positioned(
          left: 31,
          top: 0,
          child: ChunkyBox(
            fill: z.amber,
            depth: 0,
            highlight: false,
            width: 14,
            height: 61,
            radius: 0,
          ),
        ),
        Positioned(
          left: 27,
          top: 18,
          child: ChunkyBox(
            fill: z.amber,
            depth: 0,
            highlight: false,
            width: 22,
            height: 17,
            radius: 5,
          ),
        ),
        if (showDot)
          Positioned(
            right: -7,
            top: -7,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: z.coral,
                shape: BoxShape.circle,
                border: Border.all(color: z.surface, width: 3),
              ),
            ),
          ),
      ],
    );
  }
}

/// `repeating-conic-gradient(rays 0 10deg, transparent 10deg 24deg)` masked by
/// a radial fade (opaque to 25%, gone by 70% of the corner distance).
class _RaysPainter extends CustomPainter {
  final Color color;

  const _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * math.sqrt2;
    final path = Path();
    for (var a = -90.0; a < 270; a += 24) {
      path
        ..moveTo(c.dx, c.dy)
        ..arcTo(
          Rect.fromCircle(center: c, radius: r),
          a * math.pi / 180,
          10 * math.pi / 180,
          false,
        )
        ..close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color, color.withValues(alpha: 0)],
          stops: const [0, .25, .70],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}
