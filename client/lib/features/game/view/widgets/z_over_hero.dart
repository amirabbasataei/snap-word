import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_rays.dart';
import 'package:wordchain/core/widgets/z_stroked_text.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';

/// The artwork of the result screen (canvas turn 7 `ZOverA`): the loss hero
/// (broken chain, sad mascot) and the win hero (rays, confetti, happy
/// mascot). Both are authored on a [ZGame.overStage]-wide stage and scale
/// down on narrower phones.

enum ZOverEnterKind { pop, up }

/// Canvas `data-e`: `pop` (scale .6 → 1 with overshoot) or `up` (rise 14px),
/// both fading in after [delayMs]. With reduced motion the child is shown at
/// once.
class ZOverEnter extends StatefulWidget {
  final ZOverEnterKind kind;
  final int delayMs;
  final Widget child;

  const ZOverEnter({
    super.key,
    required this.kind,
    required this.delayMs,
    required this.child,
  });

  @override
  State<ZOverEnter> createState() => _ZOverEnterState();
}

class _ZOverEnterState extends State<ZOverEnter>
    with SingleTickerProviderStateMixin {
  static const _durationMs = 420;
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && !homeReducedMotion(context)) {
      _c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: widget.delayMs + _durationMs),
      )..forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final total = widget.delayMs + _durationMs;
    final t = CurvedAnimation(
      parent: c,
      curve: Interval(
        widget.delayMs / total,
        1,
        curve:
            widget.kind == ZOverEnterKind.pop
                ? Curves.easeOutBack
                : Curves.easeOut,
      ),
    );
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) {
        final v = t.value;
        final opacity = v.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child:
              widget.kind == ZOverEnterKind.pop
                  ? Transform.scale(scale: .6 + .4 * v, child: child)
                  : Transform.translate(
                    offset: Offset(0, 14 * (1 - v)),
                    child: child,
                  ),
        );
      },
    );
  }
}

/// A soft round glow (`radial-gradient(glow 0 30%, transparent 68%)`).
class _Glow extends StatelessWidget {
  final double size;
  final double stop;

  const _Glow({required this.size, required this.stop});

  @override
  Widget build(BuildContext context) {
    final glow = context.zs.glow;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [glow, glow, glow.withValues(alpha: 0)],
          stops: [0, .3 / stop, 1],
        ),
      ),
    );
  }
}

/// Loss hero: «زنجیر پاره شد!», the reason pill, the sad mascot and the end
/// of the chain with its broken link and the dashed slot of the letter that
/// was needed.
class ZOverLossHero extends StatelessWidget {
  final String title;
  final String subtitle;

  /// The last words of the chain (up to three) and the chain index of the
  /// first of them — the letters they share are coloured like in the game.
  final List<String> tail;
  final int tailStart;

  /// The letter the missed word had to start with; null on an empty chain.
  final String? requiredLetter;

  const ZOverLossHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tail,
    required this.tailStart,
    required this.requiredLetter,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZOverEnter(
          kind: ZOverEnterKind.pop,
          delayMs: 100,
          child: ZStrokedText(
            title,
            fontSize: ZGame.overTitle,
            fill: z.coral,
            stroke: ZGame.overTitleStroke,
            shadow: ZGame.overTitleShadow,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 6, right: 6),
            child: ZOverEnter(
              kind: ZOverEnterKind.pop,
              delayMs: 160,
              child: Transform.rotate(
                angle: HomeLoop.deg(-1.5),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: z.inkSurface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(color: z.coral, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: z.onInkSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: ZGame.overStage,
            height: 236,
            child: Stack(
              children: [
                const Positioned(
                  left: 118,
                  top: 6,
                  child: Opacity(
                    opacity: .6,
                    child: _Glow(size: 160, stop: .68),
                  ),
                ),
                Positioned(
                  left: (ZGame.overStage - ZGame.overMascot) / 2,
                  top: 14,
                  child: ZOverEnter(
                    kind: ZOverEnterKind.pop,
                    delayMs: 300,
                    child: const ZMascot(
                      mood: ZMascotMood.sad,
                      size: ZGame.overMascot,
                    ),
                  ),
                ),
                if (tail.isNotEmpty)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 180,
                    child: ZOverEnter(
                      kind: ZOverEnterKind.up,
                      delayMs: 500,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _BrokenChain(
                          tail: tail,
                          tailStart: tailStart,
                          requiredLetter: requiredLetter,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `tile · link · tile · link · tile ⟨broken link⟩ dashed «ر؟»`.
class _BrokenChain extends StatelessWidget {
  final List<String> tail;
  final int tailStart;
  final String? requiredLetter;

  const _BrokenChain({
    required this.tail,
    required this.tailStart,
    required this.requiredLetter,
  });

  static const _tilt = [4.0, -3.0, 3.0];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final end = tailStart + tail.length;
    final label =
        'آخر زنجیر: ${tail.join('، ')}'
        '${requiredLetter != null ? '؛ کلمهٔ بعدی با «$requiredLetter» شروع می‌شد' : ''}';

    final children = <Widget>[];
    for (var i = 0; i < tail.length; i++) {
      final index = tailStart + i;
      children.add(
        Transform.rotate(
          angle: HomeLoop.deg(_tilt[i % _tilt.length]),
          child: _WordTile(word: tail[i], index: index),
        ),
      );
      if (i < tail.length - 1) {
        children.add(
          _Link(color: zChainHueFill(context, zChainHueAt(index + 1))),
        );
      }
    }
    if (requiredLetter != null) {
      final broken = zChainHueFill(context, zChainHueAt(end));
      children
        ..add(
          Transform.translate(
            offset: const Offset(0, 4),
            child: Transform.rotate(
              angle: HomeLoop.deg(-24),
              child: _Link(color: broken, half: _Half.start),
            ),
          ),
        )
        ..add(const SizedBox(width: 22))
        ..add(
          Transform.translate(
            offset: const Offset(0, 10),
            child: Transform.rotate(
              angle: HomeLoop.deg(30),
              child: _Link(color: broken, half: _Half.end),
            ),
          ),
        )
        ..add(
          Transform.translate(
            offset: const Offset(0, 12),
            child: Transform.rotate(
              angle: HomeLoop.deg(-14),
              child: _MissingSlot(
                letter: requiredLetter!,
                ink: zChainHueInk(context, zChainHueAt(end)),
                dashed: zs.chain,
                surface: z.surface,
              ),
            ),
          ),
        );
    }

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _WordTile extends StatelessWidget {
  final String word;
  final int index;

  const _WordTile({required this.word, required this.index});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return ChunkyBox(
      fill: zs.tile,
      deep: zs.tileDeep,
      depth: 4,
      radius: 12,
      highlight: false,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      child: Text.rich(
        zChainWordSpan(
          context,
          word: word,
          index: index,
          fontSize: 17,
          color: z.ink,
        ),
        maxLines: 1,
      ),
    );
  }
}

enum _Half { start, end }

/// One chain link: a 22×12 ring, 4px band in [color] between two 2px outline
/// rings. [half] draws only the part that sticks out of its tile.
class _Link extends StatelessWidget {
  final Color color;
  final _Half? half;

  const _Link({required this.color, this.half});

  static const _w = 26.0; // 22 + the outer ring
  static const _h = 16.0;

  @override
  Widget build(BuildContext context) {
    final ring = CustomPaint(
      size: const Size(_w, _h),
      painter: _LinkPainter(color: color, outline: context.zs.outline),
    );
    if (half == null) {
      // Overlaps its two tiles by 3px each side, like the canvas margin.
      return SizedBox(
        width: _w - 6,
        height: _h,
        child: OverflowBox(maxWidth: _w, child: ring),
      );
    }
    final clipStart = half == _Half.start;
    return SizedBox(
      width: 13,
      height: _h,
      child: ClipRect(
        child: Align(
          alignment:
              clipStart
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
          widthFactor: 13 / _w,
          child: ring,
        ),
      ),
    );
  }
}

class _LinkPainter extends CustomPainter {
  final Color color;
  final Color outline;

  const _LinkPainter({required this.color, required this.outline});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 4, 18, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = outline,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.color != color || old.outline != outline;
}

/// The dashed «ر ؟» chip where the missing word would have been.
class _MissingSlot extends StatelessWidget {
  final String letter;
  final Color ink;
  final Color dashed;
  final Color surface;

  const _MissingSlot({
    required this.letter,
    required this.ink,
    required this.dashed,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DashedBorderPainter(
        radius: 12,
        color: dashed,
        strokeWidth: ZGame.outline,
        dashWidth: 6,
        dashGap: 4,
      ),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              color: context.z.ink,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              height: 1,
            ),
            children: [
              TextSpan(text: letter, style: TextStyle(color: ink)),
              const TextSpan(text: '؟'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Win hero: «بردی!» over spinning rays and falling confetti, with the happy
/// mascot hopping in front.
class ZOverWinHero extends StatelessWidget {
  final String title;

  const ZOverWinHero({super.key, required this.title});

  // (left, top, w, h, radius, delay ms, accent)
  static const _confetti = [
    (70.0, 40.0, 10.0, 16.0, 3.0, 0, 0),
    (300.0, 30.0, 12.0, 12.0, 6.0, 500, 1),
    (250.0, 70.0, 10.0, 16.0, 3.0, 900, 2),
    (120.0, 60.0, 12.0, 12.0, 3.0, 1300, 3),
    (340.0, 110.0, 10.0, 16.0, 3.0, 1700, 0),
  ];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final colors = [z.indigo, z.teal, z.coral, z.amber];
    final run = !homeReducedMotion(context);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: ZGame.overStage,
        height: 316,
        child: HomeClock(
          enabled: run,
          builder:
              (context, ms, _) => Stack(
                children: [
                  const Positioned(
                    left: 58,
                    top: 20,
                    child: _Glow(size: 280, stop: .66),
                  ),
                  Positioned(
                    left: 68,
                    top: 30,
                    width: 260,
                    height: 260,
                    child: Transform.rotate(
                      angle:
                          2 *
                          math.pi *
                          ((ms % ZGameMotion.spin) / ZGameMotion.spin),
                      child: CustomPaint(painter: ZRaysPainter(zs.rays)),
                    ),
                  ),
                  for (final c in _confetti)
                    Positioned(
                      left: c.$1,
                      top: c.$2 + _fall(ms, c.$6),
                      child: Opacity(
                        opacity: 1 - (_phase(ms, c.$6) * .9),
                        child: Container(
                          width: c.$3,
                          height: c.$4,
                          decoration: BoxDecoration(
                            color: colors[c.$7],
                            borderRadius: BorderRadius.circular(c.$5),
                            border: Border.all(color: zs.outline, width: 2),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: ZOverEnter(
                      kind: ZOverEnterKind.pop,
                      delayMs: 100,
                      child: ZStrokedText(
                        title,
                        fontSize: ZGame.overWinTitle,
                        fill: z.teal,
                        stroke: ZGame.overWinTitleStroke,
                        shadow: ZGame.overWinTitleShadow,
                      ),
                    ),
                  ),
                  Positioned(
                    left: (ZGame.overStage - ZGame.overWinMascot) / 2,
                    top: 96,
                    child: ZOverEnter(
                      kind: ZOverEnterKind.pop,
                      delayMs: 300,
                      child: const ZMascot(
                        mood: ZMascotMood.happy,
                        size: ZGame.overWinMascot,
                      ),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  static const _fallMs = 3200;

  /// 0..1 progress of a piece's fall (0 while its delay hasn't passed).
  static double _phase(double ms, int delay) =>
      ms <= delay ? 0 : ((ms - delay) % _fallMs) / _fallMs;

  static double _fall(double ms, int delay) => 150 * _phase(ms, delay);
}
