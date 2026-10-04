import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/z_icon.dart';

class _ZBottomNavItem {
  final String icon;
  final String label;

  const _ZBottomNavItem({
    required this.icon,
    required this.label,
  });
}

/// Custom bottom nav bar — square glyph tiles + Persian labels — replacing
/// the Material `BottomNavigationBar`. See REDESIGN_PLAN.md §2.2.
///
/// Glyphs are Lucide SVGs (`assets/icons/`); the active tab is marked by
/// the indigo tile + colour, as Lucide has no filled variants.
class ZBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    _ZBottomNavItem(
      icon: 'house',
      label: 'خانه',
    ),
    _ZBottomNavItem(
      icon: 'trophy',
      label: 'جدول',
    ),
    _ZBottomNavItem(
      icon: 'users',
      label: 'دوستان',
    ),
    _ZBottomNavItem(
      icon: 'user',
      label: 'من',
    ),
  ];

  const ZBottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Container(
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(top: BorderSide(color: z.line, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ZSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              return _NavButton(
                item: _items[i],
                selected: i == currentIndex,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _ZBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: ZHitTarget.min, minHeight: ZHitTarget.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZSpacing.sm, vertical: ZSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: ZTileSize.prompt,
                height: ZTileSize.prompt,
                alignment: Alignment.center,
                decoration: selected
                    ? BoxDecoration(
                        color: z.tintIndigo,
                        borderRadius: BorderRadius.circular(ZRadius.tileMin),
                      )
                    : null,
                child: ZIcon(
                  item.icon,
                  size: 22,
                  color: selected ? z.indigo : z.ink40,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: ZTypography.metaLabel.copyWith(
                  color: selected ? z.indigo : z.ink40,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
