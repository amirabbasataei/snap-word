import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// A fully-rounded chunky pill (HUD chips, tags, resume chip): a flat
/// [ChunkyBox] with 999 radius and no top highlight, [height] tall.
///
/// By default the pill is as wide as its [child] and the child is centred in
/// it — use this instead of `ChunkyBox(alignment:)`, which stretches to the
/// full width of the parent. [expand] opts into that stretch (a pill that
/// fills its row, like the resume chip).
///
/// [depth] > 0 draws the solid outline-coloured edge (pressable / HUD pills);
/// [borderWidth] is the 3px outline, or [ZGame.outlineInner] for small tags.
class ZChunkPill extends StatelessWidget {
  final Color fill;
  final double height;
  final double depth;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final bool expand;
  final Widget child;

  const ZChunkPill({
    super.key,
    required this.fill,
    required this.height,
    required this.child,
    this.depth = 0,
    this.borderWidth = ZGame.outlineInner,
    this.padding,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: fill,
      depth: depth,
      radius: 999,
      highlight: false,
      borderWidth: borderWidth,
      height: height,
      padding: padding,
      alignment: expand ? Alignment.center : null,
      child: expand ? child : Center(widthFactor: 1, child: child),
    );
  }
}
