import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_accent_disc.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';
import 'package:wordchain/features/rewards/view/widgets/reward_format.dart';

/// One prize card (canvas `ZAwards`): the coloured disc with its glyph, the
/// title and text, then the coin amount and — while unclaimed — the teal
/// «دریافت» button, or the grey «گرفتی» badge once it is claimed.
///
/// The canvas's progress bar and its dashed "still locked" card need a
/// progress the server does not track (prizes only exist once earned), so a
/// listed prize is always either ready or claimed.
class RewardTile extends StatelessWidget {
  final RewardItem item;

  /// A claim for this prize is in flight: the button reads «کمی صبر کن…» and
  /// ignores taps.
  final bool claiming;
  final VoidCallback onClaim;

  const RewardTile({
    super.key,
    required this.item,
    required this.claiming,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final face = rewardFace(item);
    final claimed = item.claimed;
    return ChunkyBox(
      fill: z.surface,
      depth: 4,
      radius: 18,
      highlight: false,
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZAccentDisc(glyph: face.glyph, accent: face.accent, dim: claimed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      face.title,
                      style: ZTypography.cardTitle.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        height: 1.35,
                        color: claimed ? z.ink60 : z.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      face.body,
                      style: ZTypography.body.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.55,
                        color: z.ink60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                Expanded(child: _Amount(coins: item.coins)),
                const SizedBox(width: 10),
                if (claimed)
                  const _ClaimedBadge()
                else
                  SizedBox(
                    width: _buttonWidth,
                    child: ZDialogButton.primary(
                      label: claiming ? 'کمی صبر کن…' : 'دریافت',
                      onTap: claiming ? null : onClaim,
                      height: 44,
                      radius: 14,
                      depth: 4,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _buttonWidth = 118.0;
}

/// «۵۰ سکه» with the small amber coin.
class _Amount extends StatelessWidget {
  final int coins;

  const _Amount({required this.coins});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      children: [
        ChunkyBox(
          fill: z.amber,
          circle: true,
          depth: 0,
          width: 16,
          height: 16,
          borderWidth: 2,
          highlight: false,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '${formatPersianNumber(coins)} سکه',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZTypography.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: z.ink60,
            ),
          ),
        ),
      ],
    );
  }
}

/// The «گرفتی» pill that replaces the button once a prize is claimed.
class _ClaimedBadge extends StatelessWidget {
  const _ClaimedBadge();

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final check = svgHex(context.zs.tealInk);
    return Semantics(
      label: 'گرفتی',
      excludeSemantics: true,
      child: ChunkyBox(
        fill: z.wash,
        depth: 0,
        radius: 14,
        highlight: false,
        width: RewardTile._buttonWidth,
        height: 44,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.string(
              '<svg viewBox="0 0 24 24" fill="none" stroke="$check" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
              width: 16,
              height: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'گرفتی',
              style: ZTypography.button.copyWith(
                fontSize: 14,
                height: 1,
                color: z.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
