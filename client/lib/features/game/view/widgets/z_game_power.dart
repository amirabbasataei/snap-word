import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_icon.dart';
import 'package:wordchain/features/home/view/widgets/home_buttons.dart';

/// Chunky power-up tile of the "A · mascot-led" game screens (canvas
/// `ZSoloA`): a raised surface tile, a coloured icon disc, the label, and a
/// corner badge. The badge shows the owned count, or — when none is owned —
/// the coin price of one use (the canvas has no slot for it).
class ZChunkyPowerupTile extends StatelessWidget {
  final String type; // hint | freeze | extra_time | shield
  final int count;
  final String label;
  final bool enabled;
  final bool dimmed;
  final String? priceLabel;
  final VoidCallback? onTap;

  const ZChunkyPowerupTile({
    super.key,
    required this.type,
    required this.count,
    required this.label,
    required this.enabled,
    this.dimmed = false,
    this.priceLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final active = enabled && !dimmed;
    final badgeText = count > 0 ? toPersianDigits(count) : priceLabel;
    final isPrice = count <= 0 && priceLabel != null;

    return Expanded(
      child: ChunkyPressable(
        depth: ZGame.depthMd - 1,
        onTap: enabled ? onTap : null,
        semanticLabel: badgeText == null ? label : '$label، $badgeText',
        builder:
            (context, depth, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: active ? 1 : .45,
                  child: ChunkyBox(
                    fill: z.surface,
                    deep: zs.tileDeep,
                    depth: depth,
                    radius: 18,
                    highlight: false,
                    height: ZGame.gamePowerTile,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Disc(type: type),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            color: z.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (badgeText != null)
                  PositionedDirectional(
                    top: -10,
                    end: -6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: ZGame.gamePowerBadge,
                      ),
                      height: ZGame.gamePowerBadge,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isPrice ? z.amber : z.inkSurface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: zs.outline,
                          width: ZGame.outlineInner,
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: isPrice ? z.onAmber : z.onInkSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final String type;

  const _Disc({required this.type});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final o = svgHex(context.zs.outline);
    final s = svgHex(z.surface);
    final (Color fill, Widget glyph) = switch (type) {
      'hint' => (
        z.amber,
        SvgPicture.string(
          '<svg viewBox="0 0 24 24" fill="none" stroke="$o" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="10" r="6" fill="$s"/><path d="M9.5 18h5M10.5 21h3"/></svg>',
          width: 18,
          height: 20,
        ),
      ),
      'extra_time' => (
        z.teal,
        SvgPicture.string(
          '<svg viewBox="0 0 24 24" fill="none" stroke="$o" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="13" r="8" fill="$s"/><path d="M12 9v4l2.5 1.5M10 2h4"/></svg>',
          width: 20,
          height: 20,
        ),
      ),
      'shield' => (
        z.coral,
        SvgPicture.string(
          '<svg viewBox="0 0 24 24" fill="$s" stroke="$o" stroke-width="2.4" stroke-linejoin="round"><path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z"/></svg>',
          width: 18,
          height: 20,
        ),
      ),
      // Not drawn in the solo canvas (multiplayer only): same disc recipe.
      _ => (z.teal, ZIcon('snowflake', size: 18, color: context.zs.outline)),
    };
    return Container(
      width: ZGame.gamePowerDisc,
      height: ZGame.gamePowerDisc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: context.zs.outline,
          width: ZGame.outlineInner,
        ),
      ),
      child: glyph,
    );
  }
}
