import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// What the mascot is feeling. Matches the canvas `ZMascot` states, plus
/// [hanging]: the idle face, one hand raised on the home chain (canvas
/// `ZHome3A`, frame 7a), the other waving.
enum ZMascotMood { idle, happy, sad, thinking, surprised, hanging }

/// The amber mascot (canvas `ZMascot.dc.html`): a plain rounded body — no
/// letter on it — with antenna, two arms, two feet and a face that changes
/// with [mood]. Every screen uses this one drawing, the home screen's chain
/// grip included ([ZMascotMood.hanging]).
///
/// Drawn on the canvas's 130×150 design grid (130×152 when hanging) and
/// scaled to [size] (width). A Rive artboard can replace it later without
/// touching a screen. With [animate] false (reduced motion) every loop rests
/// in its base pose.
class ZMascot extends StatelessWidget {
  final ZMascotMood mood;

  /// Width in logical pixels; the height keeps the canvas's 155/130 box.
  final double size;

  /// The soft ground shadow under the feet.
  final bool shadow;
  final bool animate;

  const ZMascot({
    super.key,
    this.mood = ZMascotMood.idle,
    this.size = 130,
    this.shadow = true,
    this.animate = true,
  });

  static const _gridW = 130.0;

  /// Layout box of [ZMascotMood.hanging] at `size: 130` (canvas 130×152).
  static const hangingSize = Size(130, 152);

  /// Where the raised hand holds the chain, inside the [hangingSize] box; the
  /// whole body swings about this point.
  static const hangingGrip = Offset(86, 8);

  double get _gridH => mood == ZMascotMood.hanging ? 152 : 150;

  /// Height of the layout box for a given [size] (canvas: `size*155/130`).
  static double heightFor(double size) => (size * 155 / 130).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final reduced = homeReducedMotion(context);
    final run = animate && !reduced;
    final scale = size / _gridW;
    return Semantics(
      container: true,
      label: _semantics(mood),
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height:
              mood == ZMascotMood.hanging
                  ? (size * hangingSize.height / _gridW)
                  : heightFor(size),
          child: HomeClock(
            enabled: run,
            builder:
                (context, ms, _) => Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: _gridW,
                    height: _gridH,
                    child: _build(context, ms, run),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  static String _semantics(ZMascotMood m) => switch (m) {
    ZMascotMood.idle => 'شخصیت زنجیر',
    ZMascotMood.happy => 'شخصیت زنجیر، خوشحال',
    ZMascotMood.sad => 'شخصیت زنجیر، ناراحت',
    ZMascotMood.thinking => 'شخصیت زنجیر، در فکر',
    ZMascotMood.surprised => 'شخصیت زنجیر، متعجب',
    ZMascotMood.hanging => 'شخصیت زنجیر',
  };

  Widget _build(BuildContext context, double ms, bool run) {
    final z = context.z;
    final zs = context.zs;

    // Whole-body loop, pivoting on the feet (canvas `transform-origin:
    // 65px 146px`).
    var sx = 1.0, sy = 1.0, dy = 0.0, rot = 0.0;
    var wave = 0.0, kick = 0.0;
    var pivot = const Alignment(0, 146 / 75 - 1);
    switch (mood) {
      case ZMascotMood.hanging:
        // Swings from the raised hand; the other arm waves, one leg kicks.
        // Reduced motion rests upright (the loop's first keyframe is -7°).
        rot = run ? HomeLoop.swing(ms, ZGameMotion.hang, -7, 7) : 0;
        wave = HomeLoop.swing(ms, ZGameMotion.wave, 0, -22);
        kick = HomeLoop.pingPong(ms, ZGameMotion.kick);
        pivot = Alignment(
          hangingGrip.dx / (_gridW / 2) - 1,
          hangingGrip.dy / (_gridH / 2) - 1,
        );
      case ZMascotMood.idle:
        final k = HomeLoop.pingPong(ms, 1300);
        sx = 1 + .025 * k;
        sy = 1 - .03 * k;
      case ZMascotMood.happy:
        // `hop`: squash, jump 16px, squash again every 620ms.
        final k = HomeLoop.keyframes(ms, 620, const [
          (0, 0),
          (.45, 1),
          (.9, 0),
          (1, 0),
        ]);
        dy = -16 * k;
        sx = 1.06 + (.96 - 1.06) * k;
        sy = .92 + (1.06 - .92) * k;
      case ZMascotMood.sad:
        // Slumped (scale 1.04, .94) and swaying ±2°.
        sx = 1.04;
        sy = .94;
        rot = HomeLoop.swing(ms, 2400, -2, 2);
      case ZMascotMood.thinking:
        rot = HomeLoop.swing(ms, 2000, -4, 3);
      case ZMascotMood.surprised:
        // `pop`: .7 → 1.12 → 1 once (420ms); resting pose when not animating.
        final t = run ? (ms / ZMascotTiming.pop).clamp(0.0, 1.0) : 1.0;
        final s =
            t < .55
                ? .7 + (1.12 - .7) * Curves.easeOut.transform(t / .55)
                : 1.12 + (1 - 1.12) * Curves.easeOut.transform((t - .55) / .45);
        sx = s;
        sy = s;
    }

    final paint = CustomPaint(
      size: Size(_gridW, _gridH),
      painter: _MascotPainter(
        mood: mood,
        outline: zs.outline,
        hi: zs.hi,
        amber: z.amber,
        amberDeep: z.amberDeep,
        coral: z.coral,
        teal: z.teal,
        white: z.surface.computeLuminance() > .5 ? z.surface : z.ink,
        blink:
            mood == ZMascotMood.idle || mood == ZMascotMood.hanging
                ? HomeLoop.blink(ms)
                : 1,
        wave: wave,
        kick: kick,
        tear: mood == ZMascotMood.sad ? _tear(ms) : 0,
        dots: [
          for (var i = 0; i < 3; i++)
            mood == ZMascotMood.thinking ? _dot(ms, i * 200) : 1.0,
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (shadow && mood != ZMascotMood.hanging)
          Positioned(
            left: 23,
            top: 139,
            child: Container(
              width: 84,
              height: 13,
              decoration: BoxDecoration(
                color: zs.track,
                borderRadius: BorderRadius.circular(42),
              ),
            ),
          ),
        Positioned.fill(
          child: Transform(
            alignment: pivot,
            transform:
                Matrix4.identity()
                  ..translateByDouble(0, dy, 0, 1)
                  ..rotateZ(HomeLoop.deg(rot))
                  ..scaleByDouble(sx, sy, 1, 1),
            child: paint,
          ),
        ),
      ],
    );
  }

  /// Tear drip: falls 12px and fades every 1.6s.
  static double _tear(double ms) => (ms % 1600) / 1600;

  /// Thought-bubble dots (canvas `dots`): opacity .25 → 1 → .25 rising 3px.
  static double _dot(double ms, int delay) {
    final t = ms - delay;
    if (t <= 0) return .25;
    final p = (t % 1200) / 1200;
    return p < .5 ? .25 + .75 * (p / .5) : 1 - .75 * ((p - .5) / .5);
  }
}

/// Mascot timings that are not shared with the home scene.
abstract final class ZMascotTiming {
  /// `pop` entrance, milliseconds.
  static const pop = 420.0;
}

class _MascotPainter extends CustomPainter {
  final ZMascotMood mood;
  final Color outline;
  final Color hi;
  final Color amber;
  final Color amberDeep;
  final Color coral;
  final Color teal;
  final Color white;
  final double blink; // eye scale-Y (idle, hanging)
  final double wave; // waving arm angle in degrees (hanging)
  final double kick; // 0..1 kicking-leg progress (hanging)
  final double tear; // 0..1 drip progress (sad)
  final List<double> dots; // thought-bubble opacities (thinking)

  const _MascotPainter({
    required this.mood,
    required this.outline,
    required this.hi,
    required this.amber,
    required this.amberDeep,
    required this.coral,
    required this.teal,
    required this.white,
    required this.blink,
    required this.wave,
    required this.kick,
    required this.tear,
    required this.dots,
  });

  Paint _stroke(Color c, double w) =>
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

  Paint _fill(Color c) => Paint()..color = c;

  /// A limb: outline stroke 9 with the deep-amber core (4) on top.
  void _limb(Canvas canvas, Path p) {
    canvas.drawPath(p, _stroke(outline, 9));
    canvas.drawPath(p, _stroke(amberDeep, 4));
  }

  void _hand(Canvas canvas, double x, double y, Color fill) {
    canvas.drawCircle(Offset(x, y), 7, _fill(fill));
    canvas.drawCircle(Offset(x, y), 7, _stroke(outline, 3));
  }

  Path _line(double x1, double y1, double x2, double y2) =>
      Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2);

  Path _curve(double x1, double y1, double cx, double cy, double x2, double y2) =>
      Path()
        ..moveTo(x1, y1)
        ..quadraticBezierTo(cx, cy, x2, y2);

  @override
  void paint(Canvas canvas, Size size) {
    if (mood == ZMascotMood.hanging) {
      _hangingLimbs(canvas);
      _body(canvas);
      _face(canvas);
      return;
    }
    // Legs and feet.
    _limb(canvas, _line(52, 124, 49, 141));
    _limb(canvas, _line(78, 124, 81, 141));
    for (final x in [46.0, 84.0]) {
      final r = Rect.fromCenter(center: Offset(x, 143), width: 19, height: 10);
      canvas.drawOval(r, _fill(amberDeep));
      canvas.drawOval(r, _stroke(outline, 3));
    }

    // Antenna and arms (behind the body).
    switch (mood) {
      case ZMascotMood.hanging:
        break; // returned early above
      case ZMascotMood.idle:
      case ZMascotMood.thinking:
        _antenna(canvas, _line(65, 42, 65, 23), const Offset(65, 17));
        _limb(canvas, _curve(24, 90, 12, 98, 13, 111));
        _hand(canvas, 13, 115, amber);
        if (mood == ZMascotMood.idle) {
          _limb(canvas, _curve(106, 90, 118, 98, 117, 111));
          _hand(canvas, 117, 115, amber);
        }
      case ZMascotMood.happy:
        _antenna(canvas, _line(65, 42, 65, 23), const Offset(65, 17));
        _limb(canvas, _curve(24, 84, 10, 70, 12, 53));
        _hand(canvas, 12, 48, amber);
        _limb(canvas, _curve(106, 84, 120, 70, 118, 53));
        _hand(canvas, 118, 48, amber);
      case ZMascotMood.sad:
        _antenna(canvas, _curve(65, 42, 66, 29, 77, 25), const Offset(81, 24));
        _limb(canvas, _curve(24, 96, 18, 110, 20, 121));
        _hand(canvas, 20, 125, amber);
        _limb(canvas, _curve(106, 96, 112, 110, 110, 121));
        _hand(canvas, 110, 125, amber);
      case ZMascotMood.surprised:
        _antenna(canvas, _line(65, 42, 65, 17), const Offset(65, 11));
        final rays =
            Path()
              ..moveTo(50, 4)
              ..relativeLineTo(4, 4)
              ..moveTo(80, 4)
              ..relativeLineTo(-4, 4)
              ..moveTo(65, -6)
              ..relativeLineTo(0, 4);
        canvas.drawPath(rays, _stroke(outline, 3));
        _limb(canvas, _curve(24, 86, 8, 82, 6, 69));
        _hand(canvas, 5, 64, amber);
        _limb(canvas, _curve(106, 86, 122, 82, 124, 69));
        _hand(canvas, 125, 64, amber);
    }

    _body(canvas);
    _face(canvas);

    // Thinking: the right arm crosses the face; thought bubbles rise.
    if (mood == ZMascotMood.thinking) {
      _limb(canvas, _curve(106, 92, 101, 111, 86, 108));
      _hand(canvas, 82, 107, amber);
      const bubbles = [
        (Offset(103.5, 26.5), 4.5),
        (Offset(113, 12), 6.0),
        (Offset(126.5, -5.5), 8.5),
      ];
      for (var i = 0; i < 3; i++) {
        final (c, r) = bubbles[i];
        final o = dots[i];
        final lift = Offset(0, -3 * (o - .25) / .75);
        canvas.drawCircle(c + lift, r, _fill(white.withValues(alpha: o)));
        canvas.drawCircle(
          c + lift,
          r - 1.25,
          _stroke(outline.withValues(alpha: o), 2.5),
        );
      }
    }
  }

  void _foot(Canvas canvas, double x) {
    final r = Rect.fromCenter(center: Offset(x, 143), width: 19, height: 10);
    canvas.drawOval(r, _fill(amberDeep));
    canvas.drawOval(r, _stroke(outline, 3));
  }

  /// Canvas 7a, back to front: planted leg, antenna, the hand holding the
  /// chain, the kicking leg, the waving arm (pivot at its shoulder).
  void _hangingLimbs(Canvas canvas) {
    _limb(canvas, _line(78, 124, 81, 141));
    _foot(canvas, 84);
    _antenna(canvas, _line(65, 42, 65, 23), const Offset(65, 17));
    _limb(canvas, _curve(106, 80, 122, 44, 90, 12));
    canvas.drawCircle(const Offset(86, 8), 7, _fill(amber));
    canvas.drawCircle(const Offset(86, 8), 7, _stroke(outline, 3));

    canvas.save();
    canvas.translate(-3 * kick, -3 * kick);
    _limb(canvas, _line(52, 124, 49, 141));
    _foot(canvas, 46);
    canvas.restore();

    canvas.save();
    canvas.translate(24, 80);
    canvas.rotate(HomeLoop.deg(wave));
    canvas.translate(-24, -80);
    _limb(canvas, _curve(24, 80, 8, 66, 10, 42));
    _hand(canvas, 10, 37, amber);
    canvas.restore();
  }

  void _antenna(Canvas canvas, Path stem, Offset ball) {
    _limb(canvas, stem);
    canvas.drawCircle(ball, 7, _fill(coral));
    canvas.drawCircle(ball, 7, _stroke(outline, 3));
  }

  void _body(Canvas canvas) {
    const r = 22.0;
    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(21, 40, 88, 86),
      const Radius.circular(r),
    );
    // `0 6px 0 0 amberD, 0 6px 0 3px outline`: the deep edge on its ring.
    final edge = box.shift(const Offset(0, 6));
    canvas.drawRRect(edge.inflate(3), _fill(outline));
    canvas.drawRRect(edge, _fill(amberDeep));
    final shader =
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(hi, amber), amber],
          stops: const [0, .55],
        ).createShader(box.outerRect);
    canvas.drawRRect(box, Paint()..shader = shader);
    canvas.drawRRect(box.deflate(1.5), _stroke(outline, 3));
  }

  void _eye(Canvas canvas, double cx, double cy, double rx, double ry) {
    canvas.save();
    // Blink scales the eye about the face's horizontal axis (canvas: 65, 72).
    canvas.translate(0, 72);
    canvas.scale(1, blink);
    canvas.translate(0, -72);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      _fill(outline),
    );
    canvas.restore();
  }

  void _glint(Canvas canvas, double x, double y, double r) =>
      canvas.drawCircle(Offset(x, y), r, _fill(white));

  void _cheek(Canvas canvas, double x, double y, double rx, double ry, double a) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
      _fill(coral.withValues(alpha: a)),
    );
  }

  void _openMouth(Canvas canvas, Path mouth, Offset tongue, double rx, double ry) {
    canvas.drawPath(mouth, _fill(outline));
    canvas.drawPath(mouth, _stroke(outline, 2));
    canvas.drawOval(
      Rect.fromCenter(center: tongue, width: rx * 2, height: ry * 2),
      _fill(coral),
    );
  }

  void _face(Canvas canvas) {
    switch (mood) {
      case ZMascotMood.idle:
      case ZMascotMood.hanging:
        _eye(canvas, 50, 72, 6, 8.5);
        _eye(canvas, 80, 72, 6, 8.5);
        if (blink > .5) {
          _glint(canvas, 48, 68.5, 2.2);
          _glint(canvas, 78, 68.5, 2.2);
        }
        _cheek(canvas, 35, 92, 6, 3.5, .6);
        _cheek(canvas, 95, 92, 6, 3.5, .6);
        _openMouth(
          canvas,
          Path()
            ..moveTo(55, 89)
            ..lineTo(75, 89)
            ..quadraticBezierTo(75, 104, 65, 104)
            ..quadraticBezierTo(55, 104, 55, 89)
            ..close(),
          const Offset(65, 100),
          5.5,
          3,
        );
      case ZMascotMood.happy:
        final arcs =
            Path()
              ..moveTo(43, 74)
              ..quadraticBezierTo(50, 62, 57, 74)
              ..moveTo(73, 74)
              ..quadraticBezierTo(80, 62, 87, 74);
        canvas.drawPath(arcs, _stroke(outline, 5));
        _cheek(canvas, 34, 90, 8, 4.5, .75);
        _cheek(canvas, 96, 90, 8, 4.5, .75);
        _openMouth(
          canvas,
          Path()
            ..moveTo(50, 86)
            ..lineTo(80, 86)
            ..quadraticBezierTo(80, 108, 65, 108)
            ..quadraticBezierTo(50, 108, 50, 86)
            ..close(),
          const Offset(65, 102),
          8,
          4,
        );
      case ZMascotMood.sad:
        final brows =
            Path()
              ..moveTo(41, 66)
              ..lineTo(56, 60)
              ..moveTo(74, 60)
              ..lineTo(89, 66);
        canvas.drawPath(brows, _stroke(outline, 4));
        _eye(canvas, 50, 77, 5.5, 6.5);
        _eye(canvas, 80, 77, 5.5, 6.5);
        _glint(canvas, 48.5, 74.5, 1.8);
        _glint(canvas, 78.5, 74.5, 1.8);
        _cheek(canvas, 35, 93, 6, 3.5, .4);
        _cheek(canvas, 95, 93, 6, 3.5, .4);
        canvas.drawPath(
          _curve(55, 104, 65, 93, 75, 104),
          _stroke(outline, 5),
        );
        // Tear: drips 12px and fades out.
        final drop =
            Path()
              ..moveTo(89, 82)
              ..quadraticBezierTo(93, 88, 93, 91)
              ..arcToPoint(
                const Offset(85, 91),
                radius: const Radius.circular(4),
                clockwise: true,
              )
              ..quadraticBezierTo(85, 88, 89, 82)
              ..close();
        canvas.save();
        canvas.translate(0, 12 * tear);
        final a = 1 - tear;
        canvas.drawPath(drop, _fill(teal.withValues(alpha: a)));
        canvas.drawPath(drop, _stroke(outline.withValues(alpha: a), 2));
        canvas.restore();
      case ZMascotMood.thinking:
        canvas.drawPath(_curve(70, 55, 77, 49, 85, 54), _stroke(outline, 4));
        _eye(canvas, 46, 69, 6, 8.5);
        _eye(canvas, 76, 69, 6, 8.5);
        _glint(canvas, 44, 65, 2.2);
        _glint(canvas, 74, 65, 2.2);
        _cheek(canvas, 35, 92, 6, 3.5, .6);
        final wave =
            Path()
              ..moveTo(56, 99)
              ..quadraticBezierTo(60.5, 95.5, 65, 99)
              ..quadraticBezierTo(69.5, 102.5, 74, 99);
        canvas.drawPath(wave, _stroke(outline, 4));
      case ZMascotMood.surprised:
        final brows =
            Path()
              ..moveTo(41, 55)
              ..quadraticBezierTo(50, 48, 59, 55)
              ..moveTo(71, 55)
              ..quadraticBezierTo(80, 48, 89, 55);
        canvas.drawPath(brows, _stroke(outline, 4));
        for (final x in [50.0, 80.0]) {
          canvas.drawCircle(Offset(x, 72), 9, _fill(white));
          canvas.drawCircle(Offset(x, 72), 9, _stroke(outline, 3));
          canvas.drawCircle(Offset(x, 73), 4.2, _fill(outline));
        }
        _cheek(canvas, 34, 93, 6, 3.5, .6);
        _cheek(canvas, 96, 93, 6, 3.5, .6);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(65, 101), width: 14, height: 18),
          _fill(outline),
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(65, 105), width: 8, height: 6),
          _fill(coral),
        );
    }
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.mood != mood ||
      old.blink != blink ||
      old.wave != wave ||
      old.kick != kick ||
      old.tear != tear ||
      old.outline != outline ||
      old.amber != amber ||
      old.white != white ||
      !_sameDots(old.dots, dots);

  static bool _sameDots(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
