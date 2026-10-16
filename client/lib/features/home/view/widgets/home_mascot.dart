import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';

/// What the mascot is feeling. Drives the face and the arm; the swing and
/// blink loops are the same in every mood.
enum HomeMascotMood { idle, cheer, sad }

/// «زیزو» — the amber ز tile hanging from the chain by one hand, waving with
/// the other.
///
/// Self-contained on purpose: the only inputs are [mood] and [animate]; it
/// lays itself out in a fixed [size] box and exposes [gripPoint], where the
/// chain passes through its raised hand. A Rive artboard can replace this
/// widget (same size, same grip point) without touching the screen.
class HomeMascot extends StatelessWidget {
  final HomeMascotMood mood;
  final bool animate;

  const HomeMascot({
    super.key,
    this.mood = HomeMascotMood.idle,
    this.animate = true,
  });

  static const size = Size(130, 152);

  /// Where the raised hand holds the chain, inside the [size] box.
  static const gripPoint = Offset(65, 8);

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: HomeClock(
        enabled: animate,
        builder: (context, ms, _) => _body(context, ms),
      ),
    );
  }

  Widget _body(BuildContext context, double ms) {
    final z = context.z;
    final zs = context.zs;

    // Whole body swings from the hand holding the chain.
    final swing = HomeLoop.swing(ms, ZGameMotion.hang, -7, 7);
    final kick = HomeLoop.pingPong(ms, ZGameMotion.kick);
    final wavePeriod = mood == HomeMascotMood.cheer ? 220 : ZGameMotion.wave;
    final wave =
        mood == HomeMascotMood.sad
            ? -6.0
            : HomeLoop.swing(ms, wavePeriod, 0, -22);
    final blink = HomeLoop.blink(ms);

    Widget eye(double left) => Positioned(
      left: left,
      top: 24,
      child: Transform.scale(
        scaleY: blink,
        child: Container(
          width: 12,
          height: 17,
          decoration: BoxDecoration(
            color: zs.outline,
            borderRadius: BorderRadius.circular(8.5),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 2,
                top: 2,
                child: Container(
                  width: 4,
                  height: 5,
                  decoration: BoxDecoration(
                    // The glint is always white, light or dark.
                    color:
                        z.surface.computeLuminance() > .5 ? z.surface : z.ink,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget cheek(double left) => Positioned(
      left: left,
      top: 44,
      child: Container(
        width: 12,
        height: 7,
        decoration: BoxDecoration(
          color: z.coral.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );

    return Transform.rotate(
      angle: HomeLoop.deg(swing),
      origin: gripPoint,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Legs and the arm to the grip (stroke 7 outline, round caps).
          Positioned.fill(
            child: CustomPaint(
              painter: _LimbPainter(color: zs.outline, kick: kick),
            ),
          ),
          // Waving arm, pivoting at the shoulder.
          Positioned.fill(
            child: Transform.rotate(
              angle: HomeLoop.deg(wave),
              origin: const Offset(32, 64),
              child: CustomPaint(
                painter: _ArmPainter(outline: zs.outline, hand: z.amber),
              ),
            ),
          ),
          Positioned(
            left: 21,
            top: 40,
            child: ChunkyBox(
              fill: z.amber,
              deep: z.amberDeep,
              depth: ZGame.depthLg,
              radius: 22,
              width: 88,
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  eye(20),
                  eye(50),
                  cheek(8),
                  cheek(62),
                  Positioned(left: 30, top: 46, child: _Mouth(mood: mood)),
                  PositionedDirectional(
                    end: 7,
                    bottom: 4,
                    child: Text(
                      'ز',
                      style: ZTypography.button.copyWith(
                        fontSize: 16,
                        height: 1,
                        color: z.onAmber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The raised hand that holds the chain.
          Positioned(
            left: 55,
            top: -2,
            child: ChunkyBox(
              fill: z.amber,
              circle: true,
              depth: 0,
              highlight: false,
              width: 20,
              height: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _Mouth extends StatelessWidget {
  final HomeMascotMood mood;

  const _Mouth({required this.mood});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    if (mood == HomeMascotMood.sad) {
      // Flat, slightly downturned mouth.
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 3),
        child: Container(
          width: 16,
          height: 5,
          decoration: BoxDecoration(
            color: zs.outline,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }
    return Container(
      width: 22,
      height: 18,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: zs.outline,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 9,
            child: Container(
              width: 14,
              height: 10,
              decoration: BoxDecoration(
                color: z.coral,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LimbPainter extends CustomPainter {
  final Color color;
  final double kick; // 0..1

  const _LimbPainter({required this.color, required this.kick});

  @override
  void paint(Canvas canvas, Size size) {
    final p =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round;
    // Arm from the grip to the body's top-right.
    canvas.drawLine(const Offset(65, 10), const Offset(86, 46), p);
    // Left leg kicks (−3, −3); right leg stays.
    final k = Offset(-3 * kick, -3 * kick);
    canvas.drawLine(const Offset(50, 130) + k, const Offset(42, 148) + k, p);
    canvas.drawLine(const Offset(82, 130), const Offset(90, 147), p);
  }

  @override
  bool shouldRepaint(_LimbPainter old) =>
      old.kick != kick || old.color != color;
}

class _ArmPainter extends CustomPainter {
  final Color outline;
  final Color hand;

  const _ArmPainter({required this.outline, required this.hand});

  @override
  void paint(Canvas canvas, Size size) {
    final arm =
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round;
    final path =
        Path()
          ..moveTo(34, 66)
          ..quadraticBezierTo(14, 56, 10, 32);
    canvas.drawPath(path, arm);
    canvas.drawCircle(const Offset(10, 28), 7.5, Paint()..color = hand);
    canvas.drawCircle(
      const Offset(10, 28),
      7.5,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ArmPainter old) =>
      old.outline != outline || old.hand != hand;
}
