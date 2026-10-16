import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/dashed_tile.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';

/// The vertical word chain of the "A · mascot-led" solo screen (canvas turn 7,
/// `ZSoloA`): chunky word tiles that grow towards the newest word, linked by
/// rounded chain links whose colour is the letter the two words share.
///
/// Bottom-anchored and scrollable: the newest word sits just above the input,
/// older words stay reachable by scrolling up, and a new word scrolls back
/// down.

/// Accent cycle for the shared letters. Word `i` starts in `_cycle[i % 4]` and
/// ends in the next colour (which the following word starts with); the
/// phase matches the canvas (word 4 amber → coral).
enum _Hue { coral, teal, indigo, amber }

_Hue _hueAt(int index) => _Hue.values[index % _Hue.values.length];

Color _fill(BuildContext context, _Hue h) {
  final z = context.z;
  return switch (h) {
    _Hue.coral => z.coral,
    _Hue.teal => z.teal,
    _Hue.indigo => z.indigo,
    _Hue.amber => z.amber,
  };
}

Color _ink(BuildContext context, _Hue h) {
  final zs = context.zs;
  return switch (h) {
    _Hue.coral => zs.coralInk,
    _Hue.teal => zs.tealInk,
    _Hue.indigo => zs.indigoInk,
    _Hue.amber => zs.amberInk,
  };
}

/// Words from the end that get the canvas's size ramp; earlier ones use the
/// smallest step.
const _rampFonts = [17.0, 18.0, 19.0, 20.0, 21.0, 26.0];

/// The gap between two rows (a chain link spans it and overlaps both ends).
const _rowGap = 18.0;
const _linkOverlapTop = 4.0;

double _rowHeight(bool last) =>
    last ? ZGame.gameRowTileLast : ZGame.gameRowTile;

class ZSpineChain extends StatefulWidget {
  final List<String> words;

  /// Per-word points, parallel to [words]; may be shorter (no pill then).
  final List<int> scores;

  /// Letter the next word must start with; null before the first word.
  final String? nextStartLetter;

  const ZSpineChain({
    super.key,
    required this.words,
    required this.scores,
    required this.nextStartLetter,
  });

  @override
  State<ZSpineChain> createState() => _ZSpineChainState();
}

class _ZSpineChainState extends State<ZSpineChain> {
  final _controller = ScrollController();

  /// Words present when the screen opened (a resumed game) don't drop in.
  late final int _initialLength = widget.words.length;

  /// Scrolled to the newest word (offset 0 — the list is reversed).
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final at = !_controller.hasClients || _controller.offset < 24;
      if (at != _atBottom) setState(() => _atBottom = at);
    });
  }

  @override
  void didUpdateWidget(ZSpineChain old) {
    super.didUpdateWidget(old);
    if (widget.words.length != old.words.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        if (homeReducedMotion(context)) {
          _controller.jumpTo(0);
        } else {
          _controller.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.words;
    final lastIndex = words.length - 1;
    final earlier =
        words.length > _rampFonts.length ? words.length - _rampFonts.length : 0;

    return LayoutBuilder(
      builder: (context, c) {
        final scroll = SingleChildScrollView(
          controller: _controller,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 22),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Links(
                    heights: [
                      for (var i = 0; i < words.length; i++)
                        _rowHeight(i == lastIndex),
                      ZGame.gameRowTileLast, // the "next word" slot
                    ],
                    hues: [
                      for (var i = 0; i < words.length; i++) _hueAt(i + 1),
                    ],
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < words.length; i++) ...[
                          _ChainRow(
                            key: ValueKey(i),
                            index: i,
                            word: words[i],
                            points:
                                i < widget.scores.length
                                    ? widget.scores[i]
                                    : null,
                            isLast: i == lastIndex,
                            fontSize:
                                _rampFonts[(_rampFonts.length -
                                        1 -
                                        (lastIndex - i))
                                    .clamp(0, _rampFonts.length - 1)],
                            animateIn: i >= _initialLength,
                          ),
                          const SizedBox(height: _rowGap),
                        ],
                        _NextSlot(
                          number: words.length + 1,
                          letter: widget.nextStartLetter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        // Words scrolling out under the HUD fade instead of being cut off.
        final mask = context.z.ink;
        final faded = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback:
              (rect) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // dstIn mask: only the alpha channel matters.
                colors: [mask.withValues(alpha: 0), mask],
                stops: [0, (28 / rect.height).clamp(0.0, 1.0)],
              ).createShader(rect),
          child: scroll,
        );
        // No room for the hint over the rows when the keyboard is up.
        if (earlier == 0 || c.maxHeight < 300) return faded;
        // Pinned hint that older words wait above; gone once the player has
        // scrolled up to look at them.
        return Stack(
          children: [
            Positioned.fill(child: faded),
            PositionedDirectional(
              top: 8,
              start: 0,
              end: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _atBottom ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Center(child: _EarlierChip(count: earlier)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// «↑ ۳ کلمهٔ قبلی» — marks that earlier words are scrolled off above.
class _EarlierChip extends StatelessWidget {
  final int count;

  const _EarlierChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final ink = svgHex(z.ink);
    return ChunkyBox(
      fill: z.surface,
      depth: 0,
      radius: 999,
      highlight: false,
      borderWidth: ZGame.outlineInner,
      height: 28,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.string(
            '<svg viewBox="0 0 12 12" fill="none" stroke="$ink" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10V2M2.5 5.5L6 2l3.5 3.5"/></svg>',
            width: 12,
            height: 12,
          ),
          const SizedBox(width: 6),
          Text(
            '${toPersianDigits(count)} کلمهٔ قبلی',
            style: TextStyle(
              color: z.ink,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the links *under* [child] (the rows), so every row sits in front of
/// the links that end at it. Row heights are fixed, so link positions are
/// known without measuring.
class _Links extends StatelessWidget {
  final List<double> heights;
  final List<_Hue> hues;
  final Widget child;

  const _Links({
    required this.heights,
    required this.hues,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    return CustomPaint(
      painter: _LinksPainter(
        heights: heights,
        colors: [for (final h in hues) _fill(context, h)],
        outline: zs.outline,
      ),
      child: child,
    );
  }
}

class _LinksPainter extends CustomPainter {
  final List<double> heights;
  final List<Color> colors;
  final Color outline;

  const _LinksPainter({
    required this.heights,
    required this.colors,
    required this.outline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Canvas: width 14 / height 28 / 5px border in the shared colour, outlined
    // 2.5px on both sides, shifted +7px by the asymmetric row padding.
    const w = ZGame.gameLinkWidth;
    const h = ZGame.gameLinkHeight;
    const band = 5.0;
    const ring = 2.5;
    final cx = size.width / 2 + 7;
    var y = 0.0;
    for (var i = 0; i < colors.length; i++) {
      final top = y + heights[i] - _linkOverlapTop;
      RRect pill(double width, double height, double inset) =>
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, top + h / 2),
              width: width - 2 * inset,
              height: height - 2 * inset,
            ),
            const Radius.circular(999),
          );
      canvas.drawRRect(
        pill(w + 2 * ring, h + 2 * ring, 0),
        Paint()..color = outline,
      );
      canvas.drawRRect(pill(w, h, 0), Paint()..color = colors[i]);
      canvas.drawRRect(pill(w, h, band), Paint()..color = outline);
      y += heights[i] + _rowGap;
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) =>
      old.outline != outline ||
      old.heights.length != heights.length ||
      old.colors.length != colors.length ||
      !_sameColors(old.colors);

  bool _sameColors(List<Color> other) {
    for (var i = 0; i < colors.length; i++) {
      if (colors[i] != other[i]) return false;
    }
    return true;
  }
}

class _ChainRow extends StatelessWidget {
  final int index;
  final String word;
  final int? points;
  final bool isLast;
  final double fontSize;
  final bool animateIn;

  const _ChainRow({
    super.key,
    required this.index,
    required this.word,
    required this.points,
    required this.isLast,
    required this.fontSize,
    required this.animateIn,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final first = _hueAt(index);
    final lastHue = _hueAt(index + 1);
    final chars = word.runes.toList();
    String s(Iterable<int> r) => String.fromCharCodes(r);
    final head = s(chars.take(1));
    final tail = chars.length > 1 ? s(chars.skip(chars.length - 1)) : '';
    final mid = chars.length > 2 ? s(chars.skip(1).take(chars.length - 2)) : '';

    final height = _rowHeight(isLast);
    final face = Semantics(
      label: word,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: isLast ? 150 : 110),
        child: ChunkyBox(
          fill: zs.tile,
          deep: zs.tileDeep,
          depth: isLast ? 5 : ZGame.depthMd - 1,
          radius: isLast ? 16 : 14,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          // Not `alignment:` — that would stretch the tile to the full row.
          child: Center(
            widthFactor: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: z.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize,
                    height: 1,
                  ),
                  children: [
                    TextSpan(
                      text: head,
                      style: TextStyle(color: _ink(context, first)),
                    ),
                    TextSpan(text: mid),
                    TextSpan(
                      text: tail,
                      style: TextStyle(color: _ink(context, lastHue)),
                    ),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkyBox(
          fill: z.surface,
          depth: 0,
          circle: true,
          highlight: false,
          borderWidth: ZGame.outlineInner,
          width: ZGame.gameRowIndex,
          height: ZGame.gameRowIndex,
          alignment: Alignment.center,
          child: Text(
            toPersianDigits(index + 1),
            style: TextStyle(
              color: z.ink,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(child: face),
        const SizedBox(width: 10),
        SizedBox(
          width: ZGame.gamePointsWidth,
          child: points == null ? null : _PointsPill(points: points!),
        ),
      ],
    );

    return SizedBox(
      height: height,
      child: Center(child: _DropIn(animate: animateIn, child: row)),
    );
  }
}

class _PointsPill extends StatelessWidget {
  final int points;

  const _PointsPill({required this.points});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Center(
      child: Container(
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: z.inkSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            '+${toPersianDigits(points)}',
            style: TextStyle(
              color: z.onInkSurface,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Canvas `dropin`: the newest word falls in with a springy overshoot.
class _DropIn extends StatefulWidget {
  final bool animate;
  final Widget child;

  const _DropIn({required this.animate, required this.child});

  @override
  State<_DropIn> createState() => _DropInState();
}

class _DropInState extends State<_DropIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && widget.animate && !homeReducedMotion(context)) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 520),
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
    final curve = CurvedAnimation(
      parent: c,
      curve: const Cubic(.34, 1.56, .64, 1),
    );
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder:
          (context, child) => Opacity(
            opacity: c.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -48 * (1 - curve.value)),
              child: child,
            ),
          ),
    );
  }
}

/// The dashed «حالا با «ا»» slot that closes the chain.
class _NextSlot extends StatelessWidget {
  final int number;
  final String? letter;

  const _NextSlot({required this.number, required this.letter});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final label = letter != null ? 'حالا با «$letter»' : 'اولین کلمه رو بنویس';

    Widget slot(double ms) {
      final k = HomeLoop.pingPong(ms, 900);
      return Opacity(
        opacity: 1 - .25 * k,
        child: Transform.scale(
          scale: 1 + .04 * k,
          child: CustomPaint(
            painter: DashedBorderPainter(
              radius: 16,
              color: zs.chain,
              strokeWidth: ZGame.outline,
              dashWidth: 7,
              dashGap: 4,
            ),
            child: Container(
              constraints: const BoxConstraints(minWidth: 170),
              height: ZGame.gameRowTileLast,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: z.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (letter != null) ...[
                    ChunkyBox(
                      fill: z.teal,
                      deep: null,
                      depth: ZGame.depthSm,
                      radius: 11,
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      child: Text(
                        letter!,
                        style: TextStyle(
                          color: z.onTeal,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: z.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final animate = !homeReducedMotion(context);
    return SizedBox(
      height: ZGame.gameRowTileLast,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              painter: DashedBorderPainter(
                radius: ZGame.gameRowIndex / 2,
                color: zs.chain,
                strokeWidth: ZGame.outlineInner,
                dashWidth: 5,
                dashGap: 3,
              ),
              child: SizedBox(
                width: ZGame.gameRowIndex,
                height: ZGame.gameRowIndex,
                child: Center(
                  child: Text(
                    toPersianDigits(number),
                    style: TextStyle(
                      color: z.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Semantics(
                label: label,
                excludeSemantics: true,
                child: HomeClock(
                  enabled: animate,
                  builder: (context, ms, _) => slot(ms),
                ),
              ),
            ),
            const SizedBox(width: 10 + ZGame.gamePointsWidth),
          ],
        ),
      ),
    );
  }
}
