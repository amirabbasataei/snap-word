import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/game/view/widgets/z_game_word.dart';

/// «زنجیر امروزت» (canvas `ZDailyAfterA`): the first words of the player's
/// chain as word tiles whose linking letters share a colour, rings between
/// them, and an ink «N کلمهٔ دیگر» chip for the rest.
class DailyChainCard extends StatelessWidget {
  final List<String> words;

  static const shown = 8;

  const DailyChainCard({super.key, required this.words});

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.shrink();
    final z = context.z;
    final visible = words.length > shown ? words.sublist(0, shown) : words;
    final more = words.length - visible.length;
    return Semantics(
      container: true,
      label: 'زنجیر امروزت: ${words.join('، ')}',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: z.surface,
        depth: 5,
        radius: 22,
        highlight: false,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'زنجیر امروزت',
              style: ZTypography.button.copyWith(
                fontSize: 13,
                height: 1.2,
                color: z.ink,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder:
                  (context, c) => Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        _WordTile(
                          word: visible[i],
                          index: i,
                          maxWidth: c.maxWidth,
                        ),
                        if (i < visible.length - 1 || more > 0)
                          _Ring(
                            color: zChainHueFill(context, zChainHueAt(i + 1)),
                          ),
                      ],
                      if (more > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          margin: const EdgeInsetsDirectional.only(start: 4),
                          decoration: BoxDecoration(
                            color: z.inkSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${toPersianDigits(more)} کلمهٔ دیگر',
                            style: ZTypography.button.copyWith(
                              fontSize: 12,
                              height: 1,
                              color: z.onInkSurface,
                            ),
                          ),
                        ),
                    ],
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
  final int index;
  final double maxWidth;

  const _WordTile({
    required this.word,
    required this.index,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: ChunkyBox(
          fill: zs.tile,
          deep: zs.tileDeep,
          depth: 3,
          radius: 11,
          highlight: false,
          borderWidth: ZGame.outlineInner,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                zChainWordSpan(
                  context,
                  word: word,
                  index: index,
                  fontSize: 16,
                  color: z.ink,
                ),
                maxLines: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring joining two tiles, in the colour of the letter they share.
class _Ring extends StatelessWidget {
  final Color color;

  const _Ring({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 14,
      child: CustomPaint(painter: _RingPainter(color, context.zs.outline)),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final Color outline;

  const _RingPainter(this.color, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    // A 16×10 horizontal link (3.5dp band, 2dp outline either side) squeezed
    // between the tiles' edges.
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width + 4,
      height: 10,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(999),
    ).deflate(1.75);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.5
        ..color = outline,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.outline != outline;
}
