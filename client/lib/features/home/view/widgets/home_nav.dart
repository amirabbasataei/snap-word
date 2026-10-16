import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/features/home/view/widgets/chunky.dart';
import 'package:wordchain/features/home/view/widgets/home_icons.dart';

/// Tab indices match `MainTab` (`core/utils/tab_refresh.dart`).
class HomeNav extends StatelessWidget {
  /// Pending friend requests + challenges, shown on the friends tab.
  final int friendsBadge;
  final ValueChanged<int> onSelect;

  const HomeNav({
    super.key,
    required this.friendsBadge,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Container(
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(
          top: BorderSide(color: zs.outline, width: ZGame.outline),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        math.max(12, MediaQuery.paddingOf(context).bottom + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Order = MainTab.home, board, friends, profile; the RTL row puts
          // خانه at the start (right).
          Expanded(
            child: _Tab(
              label: 'خانه',
              selected: true,
              glyph: HomeGlyph.home,
              onTap: () => onSelect(0),
            ),
          ),
          Expanded(
            child: _Tab(
              label: 'جدول',
              glyph: HomeGlyph.podium,
              onTap: () => onSelect(1),
            ),
          ),
          Expanded(
            child: _Tab(
              label: 'دوستان',
              glyph: HomeGlyph.friends,
              badge: friendsBadge,
              onTap: () => onSelect(2),
            ),
          ),
          Expanded(
            child: _Tab(
              label: 'من',
              glyph: HomeGlyph.user,
              onTap: () => onSelect(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final HomeGlyph glyph;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.glyph,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final muted = z.ink60;

    final icon =
        selected
            ? SizedBox(
              // The raised tile pokes 30px above the bar, so it only takes
              // (48 - 30) of layout height.
              height: ZGame.navTileHeight - ZGame.navLift,
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: ZGame.navTileHeight,
                maxHeight: ZGame.navTileHeight,
                child: ChunkyBox(
                  fill: z.indigo,
                  deep: z.indigoDeep,
                  depth: ZGame.depthMd,
                  radius: 16,
                  width: ZGame.navTileWidth,
                  height: ZGame.navTileHeight,
                  alignment: Alignment.center,
                  child: HomeSvg(glyph, width: 26, height: 26),
                ),
              ),
            )
            : HomeSvg(glyph, width: 30, height: 30, color: muted);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  SizedBox(height: selected ? 8 : 4),
                  Text(
                    label,
                    style: ZTypography.button.copyWith(
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      color: selected ? z.ink : muted,
                    ),
                  ),
                ],
              ),
              if (badge > 0)
                Positioned(
                  top: -6,
                  child: Transform.translate(
                    offset: const Offset(-12, 0),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: z.coral,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: z.surface, width: 2.5),
                      ),
                      child: Text(
                        toPersianDigits(badge),
                        style: ZTypography.button.copyWith(
                          fontSize: 11,
                          height: 1,
                          color: z.onCoral,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
