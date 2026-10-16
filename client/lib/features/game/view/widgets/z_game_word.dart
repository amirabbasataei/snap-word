import 'package:flutter/material.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';

/// Accent cycle for the shared letters of a chain. Word `i` starts in
/// `hue(i)` and ends in `hue(i + 1)`, which the next word starts with; the
/// phase matches the canvas (word 4 amber → coral). Used by the spine chain
/// (ZSolo) and the bubble chain (ZPlay / ZVersus).
enum ZChainHue { coral, teal, indigo, amber }

ZChainHue zChainHueAt(int index) =>
    ZChainHue.values[index % ZChainHue.values.length];

Color zChainHueFill(BuildContext context, ZChainHue h) {
  final z = context.z;
  return switch (h) {
    ZChainHue.coral => z.coral,
    ZChainHue.teal => z.teal,
    ZChainHue.indigo => z.indigo,
    ZChainHue.amber => z.amber,
  };
}

/// The same accent as text on a word tile (≥ 4.3:1 on `ZScene.tile`).
Color zChainHueInk(BuildContext context, ZChainHue h) {
  final zs = context.zs;
  return switch (h) {
    ZChainHue.coral => zs.coralInk,
    ZChainHue.teal => zs.tealInk,
    ZChainHue.indigo => zs.indigoInk,
    ZChainHue.amber => zs.amberInk,
  };
}

/// [word] with its first and last letters in the accent of the chain
/// position [index] (so two neighbours share the colour of the letter that
/// links them); the rest in [color].
TextSpan zChainWordSpan(
  BuildContext context, {
  required String word,
  required int index,
  required double fontSize,
  required Color color,
}) {
  final chars = word.runes.toList();
  String s(Iterable<int> r) => String.fromCharCodes(r);
  final head = s(chars.take(1));
  final tail = chars.length > 1 ? s(chars.skip(chars.length - 1)) : '';
  final mid = chars.length > 2 ? s(chars.skip(1).take(chars.length - 2)) : '';
  return TextSpan(
    style: TextStyle(
      color: color,
      fontWeight: FontWeight.w900,
      fontSize: fontSize,
      height: 1,
    ),
    children: [
      TextSpan(
        text: head,
        style: TextStyle(color: zChainHueInk(context, zChainHueAt(index))),
      ),
      TextSpan(text: mid),
      TextSpan(
        text: tail,
        style: TextStyle(color: zChainHueInk(context, zChainHueAt(index + 1))),
      ),
    ],
  );
}

/// «+۳۰» — points of one word on the dark `inkSurface` pill. A fixed [width]
/// (spine rows) or natural width with side padding (bubble chain).
class ZPointsPill extends StatelessWidget {
  final int points;
  final double? width;

  const ZPointsPill({super.key, required this.points, this.width});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      width: width,
      height: 22,
      padding: width == null ? const EdgeInsets.symmetric(horizontal: 8) : null,
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
    );
  }
}

/// Canvas `dropin`: the newest word falls in with a springy overshoot.
class ZDropIn extends StatefulWidget {
  final bool animate;
  final Widget child;

  const ZDropIn({super.key, required this.animate, required this.child});

  @override
  State<ZDropIn> createState() => _ZDropInState();
}

class _ZDropInState extends State<ZDropIn> with SingleTickerProviderStateMixin {
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
