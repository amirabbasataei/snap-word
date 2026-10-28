import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';

/// The hero: a chain of word tiles hanging from a peg, the mascot gripping it
/// in the middle, and the next word dropping in at the far end.
///
/// [words] must be a valid chain (each word starts with the previous word's
/// last letter), in reading order: the first word hangs nearest the peg (the
/// start/right side), the last one is the *incoming* word that bobs at the
/// end. Linking letters are accent-coloured to show the hand-off.
///
/// Self-contained for a later Rive swap: it only needs [words] and [animate], and always occupies [canvas] (the hero's design frame).
class HomeHeroChain extends StatefulWidget {
  final List<String> words;
  final bool animate;

  const HomeHeroChain({
    super.key,
    required this.words,
    this.animate = true,
  }) : assert(words.length >= 3 && words.length <= 5);

  static const canvas = Size(ZGame.heroWidth, ZGame.heroHeight);

  @override
  State<HomeHeroChain> createState() => _HomeHeroChainState();
}

class _Anchor {
  final double cx, cy, rot;
  const _Anchor(this.cx, this.cy, this.rot);
}

// Tile centres + tilt (degrees), start → end. Physical coordinates on the
// canvas: the chain starts at the top-right peg and sags left.
const _anchors = [
  _Anchor(334, 96, -38),
  _Anchor(258, 168, -24),
  _Anchor(140, 168, 24),
  _Anchor(66, 100, 36),
];
const _peg = Offset(372, 30);
const _tail = Offset(52, 60);
const _swayOrigin = Offset(198, 30);

/// Top-left of the mascot's 130×152 box (canvas 7a); its raised hand
/// ([ZMascot.hangingGrip]) is where the chain passes through.
const _mascotAt = Offset(109, 192);
const _tileHeight = 46.0;

class _Tile {
  final String word;
  final _Anchor anchor;
  final double width;
  final Color? firstInk;
  final Color? lastInk;

  const _Tile(this.word, this.anchor, this.width, this.firstInk, this.lastInk);

  /// Where the chain attaches on each side, along the tile's tilted axis.
  Offset get right {
    final r = anchor.rot * math.pi / 180;
    final d = width / 2 - 9;
    return Offset(anchor.cx + d * math.cos(r), anchor.cy + d * math.sin(r));
  }

  Offset get left {
    final r = anchor.rot * math.pi / 180;
    final d = width / 2 - 9;
    return Offset(anchor.cx - d * math.cos(r), anchor.cy - d * math.sin(r));
  }
}

class _Link {
  final Offset center;
  final double angle;
  final bool ring;
  final Color color;

  const _Link(this.center, this.angle, this.ring, this.color);
}

List<_Link> _links(List<Offset> pts, Color color) {
  final out = <_Link>[];
  var k = 0;
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final d = b - a;
    final n = math.max(1, (d.distance / 20).round());
    final angle = math.atan2(d.dy, d.dx);
    for (var j = 0; j < n; j++) {
      final t = (j + .5) / n;
      out.add(_Link(a + d * t, angle, k++ % 2 == 0, color));
    }
  }
  return out;
}

class _HomeHeroChainState extends State<HomeHeroChain> {
  List<_Tile>? _tiles;
  List<_Link>? _chainLinks;
  _Tile? _incoming;
  String? _key;
  Brightness? _brightness;
  TextStyle? _wordStyle;

  void _build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final key = widget.words.join('|');
    if (key == _key && _brightness == Theme.of(context).brightness) return;
    _key = key;
    _brightness = Theme.of(context).brightness;

    final accents = [z.indigo, z.teal, z.coral];
    final inks = [zs.indigoInk, zs.tealInk, zs.coralInk];
    final hanging = widget.words.take(4).toList();
    final incomingWord = widget.words.length > 4 ? widget.words[4] : null;
    // Junction k joins word k to word k+1 (cycling accent).
    Color? inkAt(int k) => inks[k % inks.length];

    _wordStyle = ZTypography.button.copyWith(
      fontSize: 22,
      height: 1,
      color: z.ink,
    );

    double measure(String w) {
      final tp = TextPainter(
        text: TextSpan(text: w, style: _wordStyle),
        textDirection: TextDirection.rtl,
      )..layout();
      return math.min(100, math.max(56, tp.width + 26));
    }

    final tiles = <_Tile>[
      for (var i = 0; i < hanging.length; i++)
        _Tile(
          hanging[i],
          _anchors[i],
          measure(hanging[i]),
          i > 0 ? inkAt(i - 1) : null,
          i < widget.words.length - 1 ? inkAt(i) : null,
        ),
    ];
    _tiles = tiles;
    _incoming =
        incomingWord == null
            ? null
            : _Tile(
              incomingWord,
              const _Anchor(44, 28, 18),
              66,
              inkAt(3),
              null,
            );

    final grip = _mascotAt + ZMascot.hangingGrip;
    Color acc(int k) => accents[k % accents.length];
    final links = <_Link>[
      ..._links([_peg, tiles.first.right], zs.chain),
    ];
    for (var i = 0; i < tiles.length - 1; i++) {
      final pts = <Offset>[tiles[i].left];
      if (i == 1) pts.add(grip);
      pts.add(tiles[i + 1].right);
      links.addAll(_links(pts, acc(i)));
    }
    links.addAll(_links([tiles.last.left, _tail], acc(tiles.length - 1)));
    _chainLinks = links;
  }

  @override
  Widget build(BuildContext context) {
    _build(context);
    final zs = context.zs;
    final animate = widget.animate && !homeReducedMotion(context);
    final tiles = _tiles!;

    // Static layer: peg + chain links (swings with the group but never
    // redraws).
    final staticLayer = RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 362,
            top: 20,
            child: ChunkyBox(
              fill: context.z.surface,
              circle: true,
              depth: 0,
              highlight: false,
              width: 20,
              height: 20,
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _LinksPainter(_chainLinks!, zs.outline),
            ),
          ),
        ],
      ),
    );

    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.fromSize(
          size: HomeHeroChain.canvas,
          child: HomeClock(
            enabled: animate,
            child: staticLayer,
            builder: (context, ms, staticChild) {
              final sway = HomeLoop.swing(ms, ZGameMotion.sway, -1.2, 1.2);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Transform.rotate(
                      angle: HomeLoop.deg(sway),
                      origin: _swayOrigin,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(child: staticChild!),
                          for (var i = 0; i < tiles.length; i++)
                            _positionedTile(
                              context,
                              tiles[i],
                              HomeLoop.swing(
                                ms,
                                ZGameMotion.wobble,
                                -2,
                                2,
                                delayMs: i * 300,
                              ),
                            ),
                          Positioned(
                            left: _mascotAt.dx,
                            top: _mascotAt.dy,
                            child: ZMascot(
                              mood: ZMascotMood.hanging,
                              animate: animate,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_incoming != null) _dropTile(context, ms),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _positionedTile(BuildContext context, _Tile t, double wob) {
    return Positioned(
      left: t.anchor.cx - t.width / 2,
      top: t.anchor.cy - _tileHeight / 2,
      width: t.width,
      height: _tileHeight,
      child: Transform.rotate(
        angle: HomeLoop.deg(t.anchor.rot),
        child: Transform.rotate(
          angle: HomeLoop.deg(wob),
          child: _WordTile(
            word: t.word,
            style: _wordStyle!,
            firstInk: t.firstInk,
            lastInk: t.lastInk,
          ),
        ),
      ),
    );
  }

  Widget _dropTile(BuildContext context, double ms) {
    final zs = context.zs;
    final k = HomeLoop.pingPong(ms, ZGameMotion.drop);
    final dy = -6 + 14 * k;
    final rot = -3 + 6 * k;
    final t = _incoming!;
    final scratch =
        '<svg viewBox="0 0 70 24" fill="none" stroke="${svgHex(zs.outline)}" stroke-width="3" stroke-linecap="round"><path d="M16 4l4 12M34 0l3 14M52 4l3 10"/></svg>';
    return Positioned(
      left: 11,
      top: 5 + dy,
      width: 66,
      height: _tileHeight,
      child: Transform.rotate(
        angle: HomeLoop.deg(rot),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 4,
              top: -26,
              child: SvgPicture.string(scratch, width: 70, height: 24),
            ),
            Positioned.fill(
              child: Transform.rotate(
                angle: HomeLoop.deg(t.anchor.rot),
                child: _WordTile(
                  word: t.word,
                  style: _wordStyle!,
                  firstInk: t.firstInk,
                  lastInk: null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final String word;
  final TextStyle style;
  final Color? firstInk;
  final Color? lastInk;

  const _WordTile({
    required this.word,
    required this.style,
    required this.firstInk,
    required this.lastInk,
  });

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    final runes = word.runes.toList();
    String s(Iterable<int> r) => String.fromCharCodes(r);
    final first = s(runes.take(1));
    final mid = s(runes.skip(1).take(runes.length - 2));
    final last = s(runes.skip(runes.length - 1));
    return ChunkyBox(
      fill: zs.tile,
      deep: zs.tileDeep,
      depth: ZGame.depthMd,
      radius: 14,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(
                text: first,
                style: firstInk == null ? null : TextStyle(color: firstInk),
              ),
              TextSpan(text: mid),
              TextSpan(
                text: last,
                style: lastInk == null ? null : TextStyle(color: lastInk),
              ),
            ],
          ),
          textDirection: TextDirection.rtl,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

class _LinksPainter extends CustomPainter {
  final List<_Link> links;
  final Color outline;

  const _LinksPainter(this.links, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = outline;
    for (final l in links) {
      canvas.save();
      canvas.translate(l.center.dx, l.center.dy);
      canvas.rotate(l.angle);
      if (l.ring) {
        // 30×18 ring, 6px band, 2.5px outline on both edges.
        final centre = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 24, height: 12),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          centre,
          line
            ..style = PaintingStyle.stroke
            ..strokeWidth = 11,
        );
        canvas.drawRRect(
          centre,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = l.color,
        );
      } else {
        // 24×9 filled bar with a 2.5px outline.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 29, height: 14),
            const Radius.circular(7),
          ),
          line..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 24, height: 9),
            const Radius.circular(4.5),
          ),
          Paint()..color = l.color,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) =>
      old.links != links || old.outline != outline;
}
