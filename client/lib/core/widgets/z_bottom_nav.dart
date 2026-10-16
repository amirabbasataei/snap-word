import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

enum _Glyph { home, board, friends, me }

class _ZBottomNavItem {
  final _Glyph glyph;
  final String label;

  const _ZBottomNavItem({required this.glyph, required this.label});
}

/// The bottom dock — canvas turn 7, component `ZNav`: a floating rounded
/// panel (3px outline, solid depth edge) holding four tabs with filled,
/// colourful glyphs. The selected tab is a raised chunky tile in its own
/// accent (home indigo · board amber · friends coral · me teal).
///
/// Tab indices match `MainTab` (`core/utils/tab_refresh.dart`); in RTL the
/// first item (home) sits at the right.
class ZBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Pending friend requests + challenges, shown on the friends tab while it
  /// is not selected (the canvas hides it on the selected tile).
  final int friendsBadge;

  static const friendsIndex = 2;

  static const _items = [
    _ZBottomNavItem(glyph: _Glyph.home, label: 'خانه'),
    _ZBottomNavItem(glyph: _Glyph.board, label: 'جدول'),
    _ZBottomNavItem(glyph: _Glyph.friends, label: 'دوستان'),
    _ZBottomNavItem(glyph: _Glyph.me, label: 'من'),
  ];

  const ZBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.friendsBadge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final zs = context.zs;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // The canvas floats the dock 14px above the screen edge; on notched
    // phones keep it clear of the home indicator instead.
    final bottomMargin = math.max(ZGame.dockMarginBottom, safeBottom - 12);

    // Fixed-size chrome: a huge system font scale would overflow the tabs.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Padding(
        // The raised tile pokes ~4px above the panel; reserve that so it
        // never paints over the content above the dock.
        padding: EdgeInsets.fromLTRB(
          ZGame.dockMarginH,
          4,
          ZGame.dockMarginH,
          bottomMargin,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: zs.dock,
            borderRadius: BorderRadius.circular(ZGame.dockRadius),
            border: Border.all(color: zs.outline, width: ZGame.outline),
            // White 10% sheen over the top half, pre-blended so the fill
            // stays opaque (the depth edge sits under it).
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.alphaBlend(zs.dockSheen, zs.dock), zs.dock],
              stops: const [0, .5],
            ),
            // `0 5px 0 0 dockD, 0 5px 0 3px outline`.
            boxShadow: [
              BoxShadow(
                color: zs.outline,
                offset: const Offset(0, ZGame.dockDepth),
                spreadRadius: ZGame.outline,
              ),
              BoxShadow(
                color: zs.dockDeep,
                offset: const Offset(0, ZGame.dockDepth),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ZGame.dockPaddingH,
              ZGame.dockPaddingTop,
              ZGame.dockPaddingH,
              ZGame.dockPaddingBottom,
            ),
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _DockTab(
                      item: _items[i],
                      selected: i == currentIndex,
                      badge: i == friendsIndex ? friendsBadge : 0,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockTab extends StatefulWidget {
  final _ZBottomNavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _DockTab({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_DockTab> createState() => _DockTabState();
}

class _DockTabState extends State<_DockTab> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final item = widget.item;

    final (accent, accentDeep, onAccent) = switch (item.glyph) {
      _Glyph.home => (z.indigo, z.indigoDeep, z.onIndigo),
      _Glyph.board => (z.amber, z.amberDeep, z.onAmber),
      _Glyph.friends => (z.coral, z.coralDeep, z.onCoral),
      _Glyph.me => (z.teal, z.tealDeep, z.onTeal),
    };

    return Semantics(
      button: true,
      selected: widget.selected,
      label: item.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: SizedBox(
          height: ZGame.dockTabHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: widget.selected ? 1.0 : 0.0),
            duration:
                reduced ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            builder:
                (context, t, _) => TweenAnimationBuilder<double>(
                  tween: Tween(end: _pressed ? 1.0 : 0.0),
                  duration: reduced ? Duration.zero : ZGameMotion.press,
                  builder: (context, p, _) {
                    final glyphSize =
                        lerpDouble(
                          ZGame.dockGlyph,
                          ZGame.dockGlyphSelected,
                          t,
                        )!;
                    // Pressed: the tile loses its depth edge and sinks by the
                    // same amount (chunky-button rule); a bare glyph just dips.
                    final tileDepth =
                        lerpDouble(ZGame.dockDepth, ZGame.pressedDepth, p)!;
                    final sink =
                        lerpDouble(
                          2,
                          ZGame.dockDepth - ZGame.pressedDepth,
                          t,
                        )! *
                        p;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: lerpDouble(
                            ZGame.dockGlyphTop,
                            ZGame.dockTileTop,
                            t,
                          ),
                          left: 0,
                          right: 0,
                          child: Transform.translate(
                            offset: Offset(0, sink),
                            child: Center(
                              child: SizedBox(
                                width: lerpDouble(
                                  ZGame.dockGlyph,
                                  ZGame.dockTileWidth,
                                  t,
                                ),
                                height: lerpDouble(
                                  ZGame.dockGlyph,
                                  ZGame.dockTileHeight,
                                  t,
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    if (t > 0)
                                      Positioned.fill(
                                        child: Opacity(
                                          opacity: t,
                                          child: DecoratedBox(
                                            decoration: _tileDecoration(
                                              zs,
                                              accent,
                                              accentDeep,
                                              tileDepth,
                                            ),
                                          ),
                                        ),
                                      ),
                                    _GlyphView(
                                      glyph: item.glyph,
                                      size: glyphSize,
                                      fill: Color.lerp(accent, onAccent, t)!,
                                      stroke: zs.outline,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: ZGame.dockLabelHeight,
                          child: Center(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              style: ZTypography.button.copyWith(
                                fontSize: ZGame.dockLabelSize,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                                color: Color.lerp(zs.onDock60, zs.onDock, t),
                              ),
                            ),
                          ),
                        ),
                        if (widget.badge > 0 && !widget.selected)
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Transform.translate(
                                // Canvas: `top:-8px; left:calc(50% - 26px)`,
                                // i.e. over the glyph's upper outer corner.
                                offset: Offset(
                                  Directionality.of(context) ==
                                          TextDirection.rtl
                                      ? -15
                                      : 15,
                                  -8,
                                ),
                                child: _Badge(count: widget.badge),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }

  /// `border:3px outline; background:linear-gradient(hi,transparent 55%),
  /// accent; box-shadow:0 5px 0 0 deep, 0 5px 0 3px outline`.
  static BoxDecoration _tileDecoration(
    ZScene zs,
    Color fill,
    Color deep,
    double depth,
  ) {
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(ZGame.dockTileRadius),
      border: Border.all(color: zs.outline, width: ZGame.outline),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(zs.hi, fill), fill],
        stops: const [0, .55],
      ),
      boxShadow: [
        BoxShadow(
          color: zs.outline,
          offset: Offset(0, depth),
          spreadRadius: ZGame.outline,
        ),
        BoxShadow(color: deep, offset: Offset(0, depth)),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Container(
      constraints: const BoxConstraints(
        minWidth: ZGame.dockBadge,
        minHeight: ZGame.dockBadge,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: z.coral,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: zs.outline, width: ZGame.outlineInner),
        boxShadow: [BoxShadow(color: zs.outline, offset: const Offset(0, 2))],
      ),
      // Shrink-wrapped Center: `Container(alignment:)` would expand to fill
      // the tab instead of hugging the number.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          count > 99 ? '${toPersianDigits(99)}+' : toPersianDigits(count),
          style: ZTypography.button.copyWith(
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w900,
            color: zs.onCoralSm,
          ),
        ),
      ),
    );
  }
}

/// The canvas glyphs (24×24 viewBox, `stroke-width:2.2`), token-coloured.
class _GlyphView extends StatelessWidget {
  final _Glyph glyph;
  final double size;
  final Color fill;
  final Color stroke;

  const _GlyphView({
    required this.glyph,
    required this.size,
    required this.fill,
    required this.stroke,
  });

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static const _shapes = {
    _Glyph.home:
        '<path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>',
    _Glyph.board:
        '<path d="M8.5 7h7v14h-7z"/><path d="M2 12.5h6.5V21H2z"/><path d="M15.5 10.5H22V21h-6.5z"/>',
    _Glyph.friends:
        '<circle cx="17" cy="8.5" r="3"/><path d="M13 20.5c0-3.4 1.9-5.8 4.2-5.8s4.3 2.4 4.3 5.8z"/><circle cx="9" cy="8" r="3.8"/><path d="M2 21c0-4 3-6.6 7-6.6s7 2.6 7 6.6z"/>',
    _Glyph.me:
        '<circle cx="12" cy="8" r="4.3"/><path d="M3.5 21c0-4.6 3.8-7.3 8.5-7.3s8.5 2.7 8.5 7.3z"/>',
  };

  @override
  Widget build(BuildContext context) {
    final svg =
        '<svg viewBox="0 0 24 24" fill="${_hex(fill)}" stroke="${_hex(stroke)}" '
        'stroke-width="2.2" stroke-linejoin="round">${_shapes[glyph]}</svg>';
    return SvgPicture.string(svg, width: size, height: size);
  }
}
