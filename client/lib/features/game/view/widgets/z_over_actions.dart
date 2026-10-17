import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/core/widgets/z_coin.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_icon.dart';

/// The buttons of the result screen (canvas `ZOverA`), on the shared
/// [ZDialogButton] / [ChunkyPressable] recipes.

String _shareGlyph(Color ink) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(ink)}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M8.2 10.8l7.6-4.4M8.2 13.2l7.6 4.4"/></svg>';

/// Continue offer: the wide «ادامه با ویدیو» button, then «ادامه با N سکه»
/// next to a share and a home square, and the seconds left to decide.
class ZOverContinueActions extends StatelessWidget {
  final int coinCost;
  final int secondsLeft;
  final VoidCallback onVideo;
  final VoidCallback onCoins;
  final VoidCallback onShare;

  /// «No thanks» — declines the continue (the loss stands).
  final VoidCallback onDecline;

  const ZOverContinueActions({
    super.key,
    required this.coinCost,
    required this.secondsLeft,
    required this.onVideo,
    required this.onCoins,
    required this.onShare,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZDialogButton.primary(
          label: 'ادامه با ویدیو',
          onTap: onVideo,
          height: ZGame.overPrimaryHeight,
          radius: ZGame.overPrimaryRadius,
          depth: ZGame.overPrimaryDepth,
          fontSize: 20,
          icon: ChunkyBox(
            fill: z.surface,
            circle: true,
            depth: 0,
            highlight: false,
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: SvgPicture.string(
              '<svg viewBox="0 0 20 22"><path d="M16 3L4 11l12 8z" fill="${svgHex(z.teal)}" stroke="${svgHex(zs.outline)}" stroke-width="3" stroke-linejoin="round"/></svg>',
              width: 14,
              height: 16,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ZDialogButton.primary(
                label: 'ادامه با ${toPersianDigits(coinCost)} سکه',
                onTap: onCoins,
                accent: ZDialogAccent.amber,
                height: ZGame.overSecondaryHeight,
                radius: ZGame.overSecondaryRadius,
                depth: ZGame.overSecondaryDepth,
                fontSize: 16,
                icon: const ZCoin(size: 24),
              ),
            ),
            const SizedBox(width: 10),
            _SquareButton(
              label: 'هم‌رسانی نتیجه',
              onTap: onShare,
              glyph: SvgPicture.string(
                _shareGlyph(z.ink),
                width: 22,
                height: 22,
              ),
            ),
            const SizedBox(width: 10),
            _SquareButton(
              label: 'ادامه نمی‌دم؛ بازگشت به خانه',
              onTap: onDecline,
              glyph: ZIcon('house', size: 24, color: z.ink),
            ),
          ],
        ),
        if (secondsLeft > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'فرصت ادامه: ${toPersianDigits(secondsLeft)} ثانیه',
              style: TextStyle(
                color: z.ink60,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// Final actions: the big primary CTA, then «خانه» and «هم‌رسانی».
class ZOverFinalActions extends StatelessWidget {
  final String playLabel;

  /// Null disables the primary button (the result is still being saved).
  final VoidCallback? onPlay;
  final VoidCallback onHome;
  final VoidCallback onShare;

  /// The win frame's slightly bigger CTA (66 tall, 23sp).
  final bool big;

  const ZOverFinalActions({
    super.key,
    required this.playLabel,
    required this.onPlay,
    required this.onHome,
    required this.onShare,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: onPlay == null ? .5 : 1,
          child: ZDialogButton.primary(
            label: playLabel,
            onTap: onPlay,
            height: big ? 66 : ZGame.overPrimaryHeight,
            radius: ZGame.overPrimaryRadius,
            depth: big ? 7 : ZGame.overPrimaryDepth,
            fontSize: big ? 23 : 20,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ZDialogButton.secondary(
                label: 'خانه',
                onTap: onHome,
                height: ZGame.overSecondaryHeight,
                radius: ZGame.overSecondaryRadius,
                depth: ZGame.overSecondaryDepth,
                icon: ZIcon('house', size: 20, color: z.ink),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ZDialogButton.secondary(
                label: 'هم‌رسانی',
                onTap: onShare,
                height: ZGame.overSecondaryHeight,
                radius: ZGame.overSecondaryRadius,
                depth: ZGame.overSecondaryDepth,
                icon: SvgPicture.string(
                  _shareGlyph(z.ink),
                  width: 20,
                  height: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 54×54 icon-only chunky button.
class _SquareButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Widget glyph;

  const _SquareButton({
    required this.label,
    required this.onTap,
    required this.glyph,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyPressable(
      depth: ZGame.overSecondaryDepth,
      onTap: onTap,
      semanticLabel: label,
      builder:
          (context, depth, _) => ChunkyBox(
            fill: z.surface,
            deep: context.zs.tileDeep,
            depth: depth,
            radius: ZGame.overSecondaryRadius,
            highlight: false,
            width: ZGame.overSecondaryHeight,
            height: ZGame.overSecondaryHeight,
            alignment: Alignment.center,
            child: glyph,
          ),
    );
  }
}
