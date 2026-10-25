import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_coin.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The match terms (canvas `ZLobbyA`): «ورودی ۲۰ سکه ← جایزهٔ برنده ۴۰ سکه»
/// and, underneath, what happens when nobody turns up. Both amounts come from
/// [GameConstants] (mirroring the server's `EntryFeeCoins`); when the last
/// queue attempt failed, [error] replaces the footnote so the reason sits
/// next to the retry button.
class LobbyStakeCard extends StatelessWidget {
  final String? error;

  const LobbyStakeCard({super.key, this.error});

  static String get aiFallbackNote =>
      'اگر تا ${toPersianDigits(GameConstants.matchmakingAiFallbackSec)} ثانیه '
      'حریفی پیدا نشود، با حریف هوشمند بازی می‌کنی و ورودی نمی‌دهی.';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final error = this.error;
    final ink60 = svgHex(z.ink60);
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthMd,
      radius: 22,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                Expanded(
                  child: _AmountBox(
                    label: 'ورودی',
                    amount: GameConstants.entryFeeCoins,
                    fill: z.wash,
                    labelColor: z.ink60,
                    valueColor: z.ink,
                  ),
                ),
                const SizedBox(width: 8),
                SvgPicture.string(
                  '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink)}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5M11 6l-6 6 6 6"/></svg>',
                  width: 20,
                  height: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AmountBox(
                    label: 'جایزهٔ برنده',
                    amount: GameConstants.entryFeePot,
                    fill: z.amber,
                    labelColor: z.onAmber,
                    valueColor: z.onAmber,
                    highlight: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child:
                      error == null
                          ? SvgPicture.string(
                            '<svg viewBox="0 0 24 24" fill="none" stroke="$ink60" stroke-width="2.6" stroke-linecap="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 1.5M10 2h4"/></svg>',
                            width: 20,
                            height: 20,
                          )
                          : ChunkyBox(
                            fill: z.coral,
                            circle: true,
                            depth: 0,
                            highlight: false,
                            borderWidth: ZGame.outlineInner,
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            child: Text(
                              '!',
                              style: ZTypography.button.copyWith(
                                fontSize: 12,
                                height: 1,
                                color: z.onCoral,
                              ),
                            ),
                          ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error ?? aiFallbackNote,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                      color: error == null ? z.ink60 : z.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountBox extends StatelessWidget {
  final String label;
  final int amount;
  final Color fill;
  final Color labelColor;
  final Color valueColor;
  final bool highlight;

  const _AmountBox({
    required this.label,
    required this.amount,
    required this.fill,
    required this.labelColor,
    required this.valueColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label ${toPersianDigits(amount)} سکه',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: fill,
        depth: 0,
        radius: 16,
        highlight: highlight,
        height: 58,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
        child: Row(
          children: [
            const ZCoin(size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: ZTypography.metaLabel.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: labelColor,
                      ),
                    ),
                    Text(
                      '${toPersianDigits(amount)} سکه',
                      style: ZTypography.button.copyWith(
                        fontSize: 16,
                        height: 1.2,
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
