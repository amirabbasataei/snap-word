import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/features/home/view/widgets/home_buttons.dart';
import 'package:wordchain/features/home/view/widgets/home_chest.dart';
import 'package:wordchain/features/home/view/widgets/home_daily_ribbon.dart';
import 'package:wordchain/features/home/view/widgets/home_hero_chain.dart';

/// The home hero on its 396×352 design canvas: daily ribbon, reward chest and
/// the AI button around the swinging word chain. The caller scales the whole
/// canvas to fit the screen.
class HomeHero extends StatelessWidget {
  final List<String> words;
  final bool animate;
  final bool chestReady;
  final bool dailyDot;
  final VoidCallback onDaily;
  final VoidCallback onChest;
  final VoidCallback onAi;

  const HomeHero({
    super.key,
    required this.words,
    required this.animate,
    required this.chestReady,
    required this.dailyDot,
    required this.onDaily,
    required this.onChest,
    required this.onAi,
  });

  @override
  Widget build(BuildContext context) {
    // Layering follows the canvas DOM order: ribbon, chest, AI button, then
    // the chain on top (it ignores pointers, so the ones below stay tappable).
    return SizedBox(
      width: ZGame.heroWidth,
      height: ZGame.heroHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 112,
            top: 62,
            child: HomeDailyRibbon(showDot: dailyDot, onTap: onDaily),
          ),
          Positioned(
            left: 251,
            top: 209,
            child: HomeChest(
              ready: chestReady,
              animate: animate,
              onTap: onChest,
            ),
          ),
          // Centred under x = 62 (design: 76px column at left 24).
          Positioned(
            left: 62 - HomeAiButton.width / 2,
            top: 244,
            child: HomeAiButton(onTap: onAi),
          ),
          Positioned.fill(
            child: HomeHeroChain(
              words: words,
              animate: animate,
            ),
          ),
        ],
      ),
    );
  }
}
