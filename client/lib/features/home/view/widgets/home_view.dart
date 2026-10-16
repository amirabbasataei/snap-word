import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_buttons.dart';
import 'package:wordchain/features/home/view/widgets/home_hero.dart';
import 'package:wordchain/features/home/view/widgets/home_hud.dart';
import 'package:wordchain/features/home/view/widgets/home_logo.dart';
import 'package:wordchain/features/home/view/widgets/home_motion.dart';
import 'package:wordchain/features/home/view/widgets/home_progress_path.dart';
import 'package:wordchain/features/home/view/widgets/home_scene_background.dart';

/// Everything ZHome v2 shows, as plain values — the loader
/// (`home_screen.dart`) fills it from the real providers, tests and previews
/// can fill it by hand.
class HomeViewData {
  final int coins;
  final int streak;
  final int level;
  final int xpInLevel;
  final int xpForNext;

  /// Unclaimed rewards waiting in the inbox (drives the chest).
  final int unclaimedRewards;

  final bool dailyAttempted;
  final bool hasActiveMatch;

  /// Players online right now; null when no real source exists (the button
  /// then shows a plain description instead of a number).
  final int? onlineCount;

  const HomeViewData({
    this.coins = 0,
    this.streak = 0,
    this.level = 1,
    this.xpInLevel = 0,
    this.xpForNext = 1000,
    this.unclaimedRewards = 0,
    this.dailyAttempted = false,
    this.hasActiveMatch = false,
    this.onlineCount,
  });
}

class HomeView extends StatelessWidget {
  final HomeViewData data;
  final VoidCallback onPlay;
  final VoidCallback onAi;
  final VoidCallback onOnline;
  final VoidCallback onDaily;
  final VoidCallback onChest;
  final VoidCallback onCoins;
  final VoidCallback onSettings;
  final VoidCallback onLevel;
  final VoidCallback onResume;

  const HomeView({
    super.key,
    required this.data,
    required this.onPlay,
    required this.onAi,
    required this.onOnline,
    required this.onDaily,
    required this.onChest,
    required this.onCoins,
    required this.onSettings,
    required this.onLevel,
    required this.onResume,
  });

  /// A valid chain: each word starts with the previous word's last letter.
  /// Decorative — it is the home screen's "this is the game" picture.
  static const heroWords = ['سیب', 'باران', 'نمک', 'کتاب', 'برف'];

  static const onlineFallback = 'با بازیکنان دیگر به رقابت بپرداز';

  // Heights of the non-hero blocks, used to size the hero to the screen.
  static const _hudBlock = 10.0 + ZGame.hudRowHeight;
  static const _logoBlock = 100.0;
  static const _progressBlock = 6.0 + 52.0;
  static const _playBlock = 14.0 + ZGame.playHeight + ZGame.depthXl + 3 + 4;
  static const _onlineBlock = 18.0 + ZGame.onlineHeight + ZGame.depthMd + 3;
  static const _resumeBlock = 46.0;
  static const _minHeroScale = .8;
  static const _maxHeroScale = 1.1;

  @override
  Widget build(BuildContext context) {
    final animate = !homeReducedMotion(context);
    return Stack(
      children: [
        const Positioned.fill(child: HomeSceneBackground()),
        Column(
          children: [
            Expanded(
              // The shell's floating dock overlays the bottom of this screen
              // (`extendBody`); its height arrives as bottom padding.
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final fixed =
                          _hudBlock +
                          _logoBlock +
                          _progressBlock +
                          _playBlock +
                          _onlineBlock +
                          (data.hasActiveMatch ? _resumeBlock : 0);
                      final byWidth = c.maxWidth / ZGame.heroWidth;
                      final byHeight = (c.maxHeight - fixed) / ZGame.heroHeight;
                      final scale =
                          byWidth
                              .clamp(0.0, _maxHeroScale)
                              .clamp(
                                0.0,
                                byHeight.clamp(_minHeroScale, _maxHeroScale),
                              )
                              .toDouble();
                      final heroH = ZGame.heroHeight * scale;
                      final extra = (c.maxHeight - fixed - heroH).clamp(
                        0.0,
                        double.infinity,
                      );

                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight),
                          child: Column(
                            children: [
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: HomeHud(
                                  level: data.level,
                                  levelProgress:
                                      data.xpForNext <= 0
                                          ? 0
                                          : data.xpInLevel / data.xpForNext,
                                  coins: data.coins,
                                  streak: data.streak,
                                  onLevelTap: onLevel,
                                  onCoinsTap: onCoins,
                                  onSettingsTap: onSettings,
                                ),
                              ),
                              SizedBox(height: 4 + extra * .15),
                              const HomeLogo(),
                              SizedBox(height: extra * .15),
                              SizedBox(
                                width: ZGame.heroWidth * scale,
                                height: heroH,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: HomeHero(
                                    words: heroWords,
                                    animate: animate,
                                    chestReady: data.unclaimedRewards > 0,
                                    dailyDot: !data.dailyAttempted,
                                    onDaily: onDaily,
                                    onChest: onChest,
                                    onAi: onAi,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  0,
                                ),
                                child: HomeProgressPath(
                                  level: data.level,
                                  xpInLevel: data.xpInLevel,
                                  xpForNext: data.xpForNext,
                                  onTap: onLevel,
                                ),
                              ),
                              SizedBox(height: extra * .3),
                              if (data.hasActiveMatch)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    0,
                                  ),
                                  child: _ResumeChip(onTap: onResume),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  0,
                                ),
                                child: HomePlayButton(
                                  onTap: onPlay,
                                  animate: animate,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  40,
                                  18,
                                  40,
                                  0,
                                ),
                                child: HomeOnlineButton(
                                  onTap: onOnline,
                                  subtitle:
                                      data.onlineCount == null
                                          ? onlineFallback
                                          : HomeOnlineButton.onlineCountLabel(
                                            data.onlineCount!,
                                          ),
                                ),
                              ),
                              SizedBox(height: extra * .4 + 4),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Slim "continue your game" pill, shown only while a solo/AI match is
/// waiting. The canvas has no slot for it; it keeps the resume entry point
/// the old home screen had.
class _ResumeChip extends StatelessWidget {
  final VoidCallback onTap;

  const _ResumeChip({required this.onTap});

  static const label = 'ادامهٔ بازی';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Align(
      child: ChunkyPressable(
        depth: ZGame.depthSm,
        onTap: onTap,
        semanticLabel: label,
        builder:
            (context, depth, pressed) => ChunkyBox(
              fill: z.surface,
              depth: depth,
              radius: 999,
              height: 40,
              highlight: false,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, color: z.indigo, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: ZTypography.button.copyWith(
                      fontSize: 14,
                      height: 1,
                      color: z.ink,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
