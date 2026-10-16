import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';

/// Level progress: current level badge → XP bar → next level → reward
/// milestones (chest, crown). Static.
class HomeProgressPath extends StatelessWidget {
  final int level;
  final int xpInLevel;
  final int xpForNext;
  final VoidCallback? onTap;

  const HomeProgressPath({
    super.key,
    required this.level,
    required this.xpInLevel,
    required this.xpForNext,
    this.onTap,
  });

  double get _progress =>
      xpForNext <= 0 ? 0 : (xpInLevel / xpForNext).clamp(0.0, 1.0);

  /// `۳۲۰ / ۵۰۰` — current / target. Always left-to-right so the bidi
  /// algorithm can't swap the numbers around the slash.
  static String xpLabel(int current, int target) =>
      '${formatPersianNumber(current)} / ${formatPersianNumber(target)}';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Semantics(
      label:
          'سطح ${toPersianDigits(level)}، ${xpLabel(xpInLevel, xpForNext)} امتیاز',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              ChunkyBox(
                fill: z.indigo,
                circle: true,
                depth: ZGame.depthSm,
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: Text(
                  toPersianDigits(level),
                  style: ZTypography.button.copyWith(
                    fontSize: 16,
                    height: 1,
                    color: z.onIndigo,
                  ),
                ),
              ),
              Expanded(
                flex: 100,
                child: _XpBar(
                  progress: _progress,
                  label: xpLabel(xpInLevel, xpForNext),
                ),
              ),
              _Node(
                label: toPersianDigits(level + 1),
                size: 34,
                fill: z.surface,
                text: z.ink,
              ),
              Expanded(flex: 55, child: _Track(color: zs.track)),
              _Milestone(
                number: level + 2,
                fill: z.teal,
                radius: 11,
                glyph: HomeGlyph.chest,
                glyphSize: const Size(22, 20),
              ),
              Expanded(flex: 55, child: _Track(color: zs.track)),
              _Milestone(
                number: level + 3,
                fill: z.amber,
                radius: null,
                glyph: HomeGlyph.crown,
                glyphSize: const Size(22, 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XpBar extends StatelessWidget {
  final double progress;
  final String label;

  const _XpBar({required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final style = ZTypography.button.copyWith(
      fontSize: 12,
      height: 16 / 12,
      color: z.ink,
    );
    Widget text(Color color) => Center(
      child: Text(
        label,
        textDirection: TextDirection.ltr,
        style: style.copyWith(color: color),
      ),
    );
    return Container(
      height: 22,
      decoration: BoxDecoration(
        color: z.wash,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: zs.outline, width: ZGame.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Fill grows from the start (right in RTL).
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: progress,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: z.amber,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color.alphaBlend(zs.hi, z.amber), z.amber],
                      stops: const [0, .6],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Label in `ink` over the empty track, `onAmber` over the fill, so
          // it reads in both themes.
          Positioned.fill(child: text(z.ink)),
          Positioned.fill(
            child: ClipRect(
              clipper: _FillClipper(progress, Directionality.of(context)),
              child: text(z.onAmber),
            ),
          ),
        ],
      ),
    );
  }
}

class _FillClipper extends CustomClipper<Rect> {
  final double progress;
  final TextDirection direction;

  const _FillClipper(this.progress, this.direction);

  @override
  Rect getClip(Size size) {
    final w = size.width * progress;
    return direction == TextDirection.rtl
        ? Rect.fromLTRB(size.width - w, 0, size.width, size.height)
        : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_FillClipper old) =>
      old.progress != progress || old.direction != direction;
}

class _Track extends StatelessWidget {
  final Color color;

  const _Track({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final String label;
  final double size;
  final Color fill;
  final Color text;

  const _Node({
    required this.label,
    required this.size,
    required this.fill,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      fill: fill,
      circle: true,
      depth: 0,
      highlight: false,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Text(
        label,
        style: ZTypography.button.copyWith(
          fontSize: 14,
          height: 1,
          color: text,
        ),
      ),
    );
  }
}

class _Milestone extends StatelessWidget {
  final int number;
  final Color fill;
  final double? radius; // null → circle
  final HomeGlyph glyph;
  final Size glyphSize;

  const _Milestone({
    required this.number,
    required this.fill,
    required this.radius,
    required this.glyph,
    required this.glyphSize,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return SizedBox(
      width: 38,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ChunkyBox(
            fill: fill,
            circle: radius == null,
            radius: radius ?? 0,
            depth: ZGame.depthSm,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            child: HomeSvg(
              glyph,
              width: glyphSize.width,
              height: glyphSize.height,
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: z.inkSurface,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                toPersianDigits(number),
                style: ZTypography.button.copyWith(
                  fontSize: ZGame.minLabel,
                  height: 1.3,
                  color: z.onInkSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
