import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';

/// The "chunky game object" recipe shared by every home element: a flat fill
/// with a top-half highlight, a [ZGame.outline] stroke, and a solid (zero
/// blur) depth edge in the accent's deep colour that is itself outlined.
///
/// Canvas: `border:3px solid outline; background:linear-gradient(hi,
/// transparent 55%),fill; box-shadow:0 Dpx 0 0 deep, 0 Dpx 0 3px outline`.
class ChunkyBox extends StatelessWidget {
  final Color fill;

  /// Colour of the depth edge. Null → no edge (flat object).
  final Color? deep;
  final double depth;
  final double radius;
  final bool circle;
  final double borderWidth;
  final bool highlight;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry? alignment;
  final Widget? child;

  const ChunkyBox({
    super.key,
    required this.fill,
    this.deep,
    this.depth = ZGame.depthMd,
    this.radius = 12,
    this.circle = false,
    this.borderWidth = ZGame.outline,
    this.highlight = true,
    this.width,
    this.height,
    this.padding,
    this.alignment,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    // With a deep colour: `0 Dpx 0 0 deep, 0 Dpx 0 3px outline` (the deep
    // edge sits on top of its own outline ring). Without: `0 Dpx 0 outline`.
    final shadows = <BoxShadow>[
      if (depth > 0 && deep != null) ...[
        BoxShadow(
          color: zs.outline,
          offset: Offset(0, depth),
          spreadRadius: ZGame.outline,
        ),
        BoxShadow(color: deep!, offset: Offset(0, depth)),
      ] else if (depth > 0)
        BoxShadow(color: zs.outline, offset: Offset(0, depth)),
    ];
    return Container(
      width: width,
      height: height,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: fill,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        border: Border.all(color: zs.outline, width: borderWidth),
        // A BoxDecoration gradient *replaces* the colour, so the highlight is
        // pre-blended onto the fill to stay opaque (the depth edge sits under).
        gradient:
            highlight
                ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.alphaBlend(zs.hi, fill), fill],
                  stops: const [0, .55],
                )
                : null,
        boxShadow: shadows,
      ),
      child: child,
    );
  }
}

/// `#rrggbb` for building token-coloured inline SVGs.
String svgHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
