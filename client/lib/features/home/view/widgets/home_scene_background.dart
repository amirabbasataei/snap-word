import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/motion.dart';

/// Sky gradient with depth: soft colour blobs, concentric rings, drifting
/// letters, twinkling sparkles and an edge vignette. Positions are authored on
/// the canvas' 396×812 frame and scaled to the real screen. Only the letters
/// and sparkles move; everything else is static (and repaint-isolated).
///
/// [calm] is the quieter variant used behind game screens (canvas
/// `<ZScene calm>`): no rings or sparkles, two softer blobs and four letters
/// that only drift a few pixels.
///
/// [rings] (canvas `<ZScene rings>`, default on unless [calm]) draws the three
/// concentric rings; the splash passes false and draws its own, bigger pair.
class HomeSceneBackground extends StatelessWidget {
  final bool calm;
  final bool showRings;

  const HomeSceneBackground({super.key, this.calm = false, bool? rings})
    : showRings = rings ?? !calm;

  static const _designW = 396.0;
  static const _designH = 812.0;

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    final animate = !homeReducedMotion(context);
    return LayoutBuilder(
      builder: (context, c) {
        final sx = c.maxWidth / _designW;
        final sy = c.maxHeight / _designH;
        double x(double v) => v * sx;
        double y(double v) => v * sy;
        final blobScale = sx < sy ? sx : sy; // keep circles round

        Widget circle(double l, double t, double d, Color color) => Positioned(
          left: x(l),
          top: y(t),
          width: d * blobScale,
          height: d * blobScale,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [zs.sky1, zs.sky2, zs.sky3],
              stops: const [0, .5, 1],
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              RepaintBoundary(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (calm) ...[
                      circle(-90, 440, 300, zs.blobIndigo),
                      circle(396 + 110 - 280, 70, 280, zs.blobTeal),
                    ] else ...[
                      circle(-90, 420, 300, zs.blobIndigo),
                      circle(396 + 110 - 280, 90, 280, zs.blobTeal),
                      if (showRings) ...[
                        circle(8, 110, 380, zs.ring),
                        circle(68, 170, 260, zs.ring),
                        circle(128, 230, 140, zs.ring),
                      ],
                    ],
                  ],
                ),
              ),
              Positioned.fill(
                child: HomeClock(
                  enabled: animate,
                  builder:
                      (context, ms, _) => Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (calm)
                            ..._calmLetters(context, ms, x, y)
                          else ...[
                            _letter(
                              context,
                              'م',
                              x(24),
                              y(96),
                              16,
                              ms,
                              7200,
                              0,
                              alpha: .5,
                            ),
                            _letter(
                              context,
                              'ش',
                              x(300),
                              y(150),
                              18,
                              ms,
                              8000,
                              900,
                              alpha: .5,
                            ),
                            _letter(
                              context,
                              'ل',
                              x(200),
                              y(470),
                              15,
                              ms,
                              6800,
                              300,
                              alpha: .5,
                            ),
                            _letter(
                              context,
                              'ت',
                              x(350),
                              y(420),
                              30,
                              ms,
                              5600,
                              600,
                              alpha: .8,
                              rotation: 14,
                            ),
                            _letter(
                              context,
                              'د',
                              x(10),
                              y(300),
                              28,
                              ms,
                              5200,
                              1200,
                              alpha: .8,
                              rotation: -12,
                            ),
                            _letter(
                              context,
                              'ژ',
                              x(-14),
                              y(520),
                              64,
                              ms,
                              4200,
                              0,
                              outlined: true,
                              rotation: -16,
                            ),
                            _letter(
                              context,
                              'ق',
                              x(338),
                              y(250),
                              54,
                              ms,
                              4600,
                              700,
                              outlined: true,
                              rotation: 12,
                            ),
                            _sparkle(x(60), y(200), 16, context.z.amber, ms, 0),
                            _sparkle(
                              x(300),
                              y(118),
                              12,
                              context.z.teal,
                              ms,
                              600,
                            ),
                            _sparkle(
                              x(250),
                              y(470),
                              14,
                              context.z.coral,
                              ms,
                              1200,
                            ),
                            _sparkle(
                              x(110),
                              y(440),
                              11,
                              context.z.indigo,
                              ms,
                              300,
                            ),
                          ],
                        ],
                      ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _VignettePainter(zs.vignette)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Canvas `data-a="drift"`: ±6px over 9s, four letters at fixed spots.
  List<Widget> _calmLetters(
    BuildContext context,
    double ms,
    double Function(double) x,
    double Function(double) y,
  ) {
    return [
      _letter(
        context,
        'د',
        x(14),
        y(150),
        22,
        ms,
        9000,
        0,
        alpha: .45,
        rotation: -12,
        travel: 6,
      ),
      _letter(
        context,
        'ت',
        x(356),
        y(330),
        24,
        ms,
        9000,
        1500,
        alpha: .45,
        rotation: 14,
        travel: 6,
      ),
      _letter(
        context,
        'ژ',
        x(-18),
        y(600),
        60,
        ms,
        9000,
        800,
        outlined: true,
        alpha: .6,
        rotation: -16,
        travel: 6,
      ),
      _letter(
        context,
        'ق',
        x(350),
        y(90),
        48,
        ms,
        9000,
        2400,
        outlined: true,
        alpha: .6,
        rotation: 12,
        travel: 6,
      ),
    ];
  }

  Widget _letter(
    BuildContext context,
    String ch,
    double left,
    double top,
    double size,
    double ms,
    int period,
    int delay, {
    double alpha = 1,
    double rotation = 0,
    bool outlined = false,
    double travel = 12,
  }) {
    final zs = context.zs;
    final dy = -travel * HomeLoop.pingPong(ms, period, delayMs: delay);
    final style =
        outlined
            ? ZTypography.display.copyWith(
              fontSize: size,
              height: 1,
              foreground:
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..strokeJoin = StrokeJoin.round
                    ..color = zs.particleNear,
            )
            : ZTypography.display.copyWith(
              fontSize: size,
              height: 1,
              color: zs.particle.withValues(alpha: zs.particle.a * alpha),
            );
    return Positioned(
      left: left,
      top: top + dy,
      child: Transform.rotate(
        angle: HomeLoop.deg(rotation),
        child: Opacity(
          opacity: outlined ? alpha : 1,
          child: Text(ch, style: style, textDirection: TextDirection.rtl),
        ),
      ),
    );
  }

  Widget _sparkle(
    double left,
    double top,
    double size,
    Color color,
    double ms,
    int delay,
  ) {
    final k = HomeLoop.twinkle(ms, delayMs: delay);
    final scale = .4 + .6 * k;
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Opacity(
        opacity: .3 + .7 * k,
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(painter: SparklePainter(color)),
        ),
      ),
    );
  }
}

/// Four-point star used for sparkles (canvas `clip-path: polygon(...)`).
class SparklePainter extends CustomPainter {
  final Color color;

  const SparklePainter(this.color);

  static const _pts = [
    (50.0, 0.0),
    (62.0, 38.0),
    (100.0, 50.0),
    (62.0, 62.0),
    (50.0, 100.0),
    (38.0, 62.0),
    (0.0, 50.0),
    (38.0, 38.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final dx = _pts[i].$1 / 100 * size.width;
      final dy = _pts[i].$2 / 100 * size.height;
      i == 0 ? path.moveTo(dx, dy) : path.lineTo(dx, dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(SparklePainter old) => old.color != color;
}

/// `radial-gradient(ellipse 120% 85% at 50% 40%, transparent 55%, vignette)`.
class _VignettePainter extends CustomPainter {
  final Color color;

  const _VignettePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rx = size.width * 1.2;
    final ry = size.height * .85;
    canvas.save();
    canvas.translate(size.width * .5, size.height * .4);
    canvas.scale(1, ry / rx);
    final r = Rect.fromCircle(center: Offset.zero, radius: rx);
    final shader = RadialGradient(
      colors: [color.withValues(alpha: 0), color.withValues(alpha: 0), color],
      stops: const [0, .55, 1],
    ).createShader(r);
    canvas.drawRect(
      Rect.fromLTRB(
        -size.width * 3,
        -size.height * 3,
        size.width * 3,
        size.height * 3,
      ),
      Paint()..shader = shader,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.color != color;
}
