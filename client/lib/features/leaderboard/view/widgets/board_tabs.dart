import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';

/// The four-way segmented control under the title (canvas `ZBoardA`): a
/// surface plate with the selected segment in ink.
class BoardTabs extends StatelessWidget {
  final BoardTab selected;
  final ValueChanged<BoardTab> onSelect;

  const BoardTabs({super.key, required this.selected, required this.onSelect});

  static const labels = {
    BoardTab.weekly: 'این هفته',
    BoardTab.daily: 'امروز',
    BoardTab.allTime: 'همیشه',
    BoardTab.friends: 'دوستان',
  };

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final animate = !homeReducedMotion(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyBox(
        fill: z.surface,
        depth: 3,
        radius: 14,
        highlight: false,
        height: 46,
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (final tab in BoardTab.values) ...[
              if (tab != BoardTab.values.first) const SizedBox(width: 3),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: tab == selected,
                  label: labels[tab],
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(tab),
                    child: AnimatedContainer(
                      duration:
                          animate
                              ? const Duration(milliseconds: 140)
                              : Duration.zero,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color:
                            tab == selected ? z.inkSurface : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labels[tab]!,
                          maxLines: 1,
                          style: ZTypography.button.copyWith(
                            fontSize: 13,
                            color: tab == selected ? z.onInkSurface : z.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
