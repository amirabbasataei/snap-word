import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';

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

/// «بازی» — the huge primary button. Teal, 8px edge, idle pulse (paused while
/// pressed and when reduced motion is on).
class HomePlayButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool animate;

  const HomePlayButton({super.key, required this.onTap, this.animate = true});

  static const label = 'بازی';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return HomeClock(
      enabled: animate,
      builder:
          (context, ms, child) =>
              Transform.scale(scale: HomeLoop.pulse(ms), child: child),
      child: ChunkyPressable(
        depth: ZGame.depthXl,
        onTap: onTap,
        semanticLabel: label,
        builder:
            (context, depth, pressed) => ChunkyBox(
              fill: z.teal,
              deep: z.tealDeep,
              depth: depth,
              radius: ZGame.playRadius,
              height: ZGame.playHeight,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: ZTypography.button.copyWith(
                      fontSize: 40,
                      height: 1,
                      color: z.onTeal,
                      shadows: [
                        Shadow(color: z.tealDeep, offset: const Offset(0, 3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ChunkyBox(
                    fill: z.surface,
                    circle: true,
                    depth: 0,
                    highlight: false,
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    child: const HomeSvg(HomeGlyph.play, width: 20, height: 22),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

/// «رویارویی آنلاین» — coral secondary with player avatars and an online
/// count line. [subtitle] is whatever the caller can honestly say.
class HomeOnlineButton extends StatelessWidget {
  final VoidCallback onTap;
  final String subtitle;

  const HomeOnlineButton({
    super.key,
    required this.onTap,
    required this.subtitle,
  });

  static const title = 'رویارویی آنلاین';
  static const onlineSuffix = 'نفر آنلاین';

  /// `۳٬۴۰۱ نفر آنلاین`.
  static String onlineCountLabel(int count) =>
      '${formatPersianNumber(count)} $onlineSuffix';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;

    Widget avatar(Color fill, Color ink, String ch, int slot) =>
        PositionedDirectional(
          // Each avatar overlaps the previous by 9px.
          start: slot * 21.0,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: zs.outline, width: ZGame.outlineInner),
            ),
            child: Text(
              ch,
              style: ZTypography.button.copyWith(
                fontSize: 13,
                height: 1,
                color: ink,
              ),
            ),
          ),
        );

    return ChunkyPressable(
      depth: ZGame.depthMd,
      onTap: onTap,
      semanticLabel: title,
      builder:
          (context, depth, pressed) => ChunkyBox(
            fill: z.coral,
            deep: z.coralDeep,
            depth: depth,
            radius: ZGame.onlineRadius,
            height: ZGame.onlineHeight,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decorative player avatars (not real opponents).
                SizedBox(
                  width: 72,
                  height: 30,
                  child: Stack(
                    children: [
                      avatar(z.indigo, z.onIndigo, 'م', 0),
                      avatar(z.amber, z.onAmber, 'س', 1),
                      avatar(z.surface, z.ink, '+', 2),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ZTypography.button.copyWith(
                        fontSize: 19,
                        height: 1.1,
                        color: z.onCoral,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: z.onCoral,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          subtitle,
                          style: ZTypography.button.copyWith(
                            fontSize: ZGame.minLabel,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            color: z.onCoral,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}

/// Round «حریف هوشمند» button with its label pill.
class HomeAiButton extends StatelessWidget {
  final VoidCallback onTap;

  const HomeAiButton({super.key, required this.onTap});

  static const label = 'حریف هوشمند';

  /// Column width; the label pill is wider than the 64px disc.
  static const width = 96.0;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyPressable(
            depth: ZGame.depthMd,
            onTap: onTap,
            semanticLabel: label,
            builder:
                (context, depth, pressed) => ChunkyBox(
                  fill: z.indigo,
                  deep: z.indigoDeep,
                  circle: true,
                  depth: depth,
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  child: const HomeSvg(HomeGlyph.robot, width: 36, height: 34),
                ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: z.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: zs.outline, width: 2.5),
              ),
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: ZTypography.button.copyWith(
                  fontSize: ZGame.minLabel,
                  height: 1,
                  color: z.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
