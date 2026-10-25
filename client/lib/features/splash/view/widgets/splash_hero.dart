import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/home/view/widgets/home_logo.dart';
import 'package:wordchain/features/splash/view/widgets/splash_timeline.dart';

/// The splash artwork (canvas `ZSplash`): two rings and a glow, the «زنجیر»
/// tiles falling onto each other, the mascot dropping onto the chain, four
/// sparkles and the tagline pill. Authored on the canvas's grid ([width] ×
/// [height], the 396×812 frame cropped to the part that moves) and scaled
/// down by the caller on narrow phones — positions are physical because the
/// wordmark reads «ز» on the right whatever the app's direction.
///
/// [ms] is the elapsed time on the [SplashTimeline]; with [animate] false
/// (reduced motion) the finished composition is drawn and the mascot rests.
class SplashHero extends StatelessWidget {
  final double ms;
  final bool animate;

  const SplashHero({super.key, required this.ms, required this.animate});

  static const width = 396.0;
  static const height = 400.0;

  static const _tileW = 60.0;
  static const _tileH = 66.0;
  static const _tileStep = 70.0; // 60 tile + 22 link − 2 × 6 overlap
  static const _rowTop = 170.0;
  static const _baseTilt = [-4.0, 3.0, -1.0, 4.0, -3.0];

  double get _t => animate ? ms : SplashTimeline.introMs;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final t = _t;
    final sparkColors = [z.amber, z.teal, z.coral, z.indigo];
    const sparkSpots = [
      (112.0, 130.0, 18.0),
      (270.0, 122.0, 16.0),
      (96.0, 70.0, 12.0),
      (290.0, 62.0, 13.0),
    ];
    final (mdy, msx, msy) = SplashTimeline.mascot(t);
    final dip = SplashTimeline.rowDip(t);
    final glow = SplashTimeline.glow(t);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ring(SplashTimeline.ring(t, 0), 400, -2, 0, zs.ring),
          _ring(SplashTimeline.ring(t, 1), 280, 58, 60, zs.ring),
          Positioned(
            left: 68,
            top: 70,
            child: Opacity(
              opacity: glow.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: .4 + .6 * glow,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [zs.glow, zs.glow.withValues(alpha: 0)],
                      stops: const [0, .68],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 138,
            top: 33,
            width: 120,
            height: ZMascot.heightFor(120),
            child: Transform.translate(
              offset: Offset(0, mdy),
              child: Transform.scale(
                scaleX: msx,
                scaleY: msy,
                // Canvas `transform-origin: 60px 140px`: pivots near the feet.
                origin: Offset(0, 140 - ZMascot.heightFor(120) / 2),
                alignment: Alignment.center,
                child: ZMascot(size: 120, shadow: false, animate: animate),
              ),
            ),
          ),
          Positioned(
            left: (width - _rowWidth) / 2,
            top: _rowTop,
            width: _rowWidth,
            height: _tileH + ZGame.depthLg,
            child: Transform.translate(
              offset: Offset(0, dip),
              child: Semantics(
                label: 'زنجیر',
                excludeSemantics: true,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < 4; i++) _link(i, t, zs.outline),
                    for (var i = 0; i < 5; i++) _tile(context, i, t),
                  ],
                ),
              ),
            ),
          ),
          for (var i = 0; i < 4; i++)
            if (animate && SplashTimeline.spark(t, i) != null)
              Positioned(
                left: sparkSpots[i].$1,
                top: sparkSpots[i].$2,
                child: _Spark(
                  t: SplashTimeline.spark(t, i)!,
                  size: sparkSpots[i].$3,
                  color: sparkColors[i],
                ),
              ),
          Positioned(
            left: 0,
            right: 0,
            top: 272,
            child: Center(child: _Tag(t: SplashTimeline.tag(t))),
          ),
        ],
      ),
    );
  }

  static const _rowWidth = 5 * _tileW + 4 * (_tileStep - _tileW);

  Widget _ring(double k, double d, double left, double top, Color color) {
    return Positioned(
      left: left,
      top: top,
      width: d,
      height: d,
      child: Opacity(
        opacity: k.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: .2 + .8 * k,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  /// Tile [i], «ز» first and rightmost; the row is laid out right to left.
  Widget _tile(BuildContext context, int i, double t) {
    final z = context.z;
    final zs = context.zs;
    final (letter, fill, deep, ink) = switch (i) {
      0 => ('ز', z.indigo, z.indigoDeep, z.onIndigo),
      1 => ('ن', z.teal, z.tealDeep, z.onTeal),
      2 => ('ج', zs.tile, zs.tileDeep, zs.amberInk),
      3 => ('ی', z.coral, z.coralDeep, z.onCoral),
      _ => ('ر', z.indigo, z.indigoDeep, z.onIndigo),
    };
    final k = SplashTimeline.tile(t, i);
    return Positioned(
      left: (4 - i) * _tileStep,
      top: 0,
      child: Opacity(
        opacity: t < 250 + i * 130.0 ? 0 : 1,
        child: Transform.translate(
          offset: Offset(0, -460 * (1 - k)),
          child: Transform.rotate(
            angle: HomeLoop.deg(
              _baseTilt[i] + SplashTimeline.tileSpin[i] * (1 - k),
            ),
            child: ChunkyBox(
              fill: fill,
              deep: deep,
              depth: ZGame.depthLg,
              radius: 17,
              width: _tileW,
              height: _tileH,
              alignment: Alignment.center,
              child: Text(
                letter,
                style: ZTypography.display.copyWith(
                  fontSize: 36,
                  height: 1,
                  color: ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The oval link between tile [i] and i+1 (22×14, 4dp stroke), drawn under
  /// the tiles so they overlap its ends.
  Widget _link(int i, double t, Color outline) {
    final s = SplashTimeline.link(t, i);
    final centre = (3 - i) * _tileStep + _tileStep - (_tileStep - _tileW) / 2;
    return Positioned(
      left: centre - 11,
      top: (_tileH - 14) / 2,
      child: Opacity(
        opacity: (s * 2).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: s,
          child: Container(
            width: 22,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: outline, width: 4),
            ),
          ),
        ),
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  final double t;
  final double size;
  final Color color;

  const _Spark({required this.t, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t > .95 ? 0 : 1,
      child: Transform.rotate(
        angle: math.pi * t,
        child: Transform.scale(
          scale: SplashTimeline.sparkScale(t),
          child: CustomPaint(
            size: Size.square(size),
            painter: _StarPainter(color),
          ),
        ),
      ),
    );
  }
}

/// The canvas's four-point star
/// (`polygon(50% 0, 62% 38%, 100% 50%, 62% 62%, 50% 100%, 38% 62%, 0 50%, 38% 38%)`).
class _StarPainter extends CustomPainter {
  final Color color;

  const _StarPainter(this.color);

  static const _pts = [
    (.5, 0.0),
    (.62, .38),
    (1.0, .5),
    (.62, .62),
    (.5, 1.0),
    (.38, .62),
    (0.0, .5),
    (.38, .38),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final (x, y) = _pts[i];
      i == 0
          ? path.moveTo(x * size.width, y * size.height)
          : path.lineTo(x * size.width, y * size.height);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

/// «حرف آخر، حرف اول!» — the ink pill tilted −2° with a coral edge, popping in
/// with a spin. The same string and look as `HomeLogo`'s tagline, larger.
class _Tag extends StatelessWidget {
  final double t;

  const _Tag({required this.t});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: t,
        child: Transform.rotate(
          angle: HomeLoop.deg(-2 - 14 * (1 - t)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 9, 18, 10),
            decoration: BoxDecoration(
              color: z.inkSurface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(color: z.coral, offset: const Offset(0, 4)),
              ],
            ),
            child: Text(
              HomeLogo.tagline,
              style: ZTypography.button.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1,
                color: z.onInkSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
