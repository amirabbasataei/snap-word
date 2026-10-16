import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';

/// Press behaviour shared by every chunky button: on tap-down the solid edge
/// shrinks to [ZGame.pressedDepth] and the face sinks by the difference.
class ChunkyPressable extends StatefulWidget {
  final double depth;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Builds the face for the current [depth] (resting or pressed).
  final Widget Function(BuildContext context, double depth, bool pressed)
  builder;

  const ChunkyPressable({
    super.key,
    required this.depth,
    required this.builder,
    this.onTap,
    this.semanticLabel,
  });

  @override
  State<ChunkyPressable> createState() => _ChunkyPressableState();
}

class _ChunkyPressableState extends State<ChunkyPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final sink = widget.depth - ZGame.pressedDepth;
    final depth = _pressed ? ZGame.pressedDepth : widget.depth;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        child: AnimatedContainer(
          duration: ZGameMotion.press,
          curve: Curves.easeOut,
          // Reserve the resting edge so layout doesn't jump on press.
          padding: EdgeInsets.only(bottom: widget.depth + ZGame.outline),
          transform: Matrix4.translationValues(0, _pressed ? sink : 0, 0),
          child: widget.builder(context, depth, _pressed),
        ),
      ),
    );
  }
}
