import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/motion.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/link_position.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';

/// The four-way segmented control under the title (canvas `ZBoardA`): a
/// surface plate with the selected segment in ink.
class BoardTabs extends StatelessWidget {
  final BoardTab selected;
  final ValueChanged<BoardTab> onSelect;

  const BoardTabs({super.key, required this.selected, required this.onSelect});

  static const labels = {
    BoardTab.weekly: 'این هفته',
    BoardTab.daily: 'چالش',
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

/// The three Daily Challenge types under «چالش» — «حرف اول / حرف دوم / حرف
/// سوم», one board each. A lighter sibling of [BoardTabs] (no depth edge).
class DailyVariantTabs extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const DailyVariantTabs({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final animate = !homeReducedMotion(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Row(
        children: [
          for (final variant in GameConstants.dailyVariants) ...[
            if (variant != GameConstants.dailyVariants.first)
              const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                button: true,
                selected: variant == selected,
                label: 'چالش ${linkVariantName(variant)}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(variant),
                  child: AnimatedContainer(
                    duration:
                        animate
                            ? const Duration(milliseconds: 140)
                            : Duration.zero,
                    height: 36,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: variant == selected ? z.indigo : z.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.zs.outline, width: 2),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        linkVariantName(variant),
                        maxLines: 1,
                        style: ZTypography.button.copyWith(
                          fontSize: 13,
                          color: variant == selected ? z.onIndigo : z.ink,
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
    );
  }
}
