import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/features/friends/cubit/invite_code_cubit.dart';

/// «با کد دعوت، ۵۰ سکه بگیر» (canvas `ZFriendsA`): the player's own referral
/// code and a share button. The code is the real one from `GET /referral/me`
/// (6 letters/digits — shown as is, left-to-right, so a friend can type it);
/// the 50 coins are the inviter reward the server really grants per invited
/// friend (`config.CoinReferralInviter`). Redeeming someone else's code lives
/// in `ReferralBottomSheet` and is untouched.
class FriendsInviteCard extends StatelessWidget {
  final InviteCodeState state;
  final VoidCallback onShare;
  final VoidCallback onRetry;

  const FriendsInviteCard({
    super.key,
    required this.state,
    required this.onShare,
    required this.onRetry,
  });

  static const title = 'با کد دعوت، ۵۰ سکه بگیر';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final ready = state.status == InviteCodeStatus.ready;
    final failed = state.status == InviteCodeStatus.failed;
    final onAmber = z.onAmber;
    final sub = ZTypography.metaLabel.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 1.3,
      color: onAmber,
    );
    return ChunkyBox(
      fill: z.amber,
      deep: z.amberDeep,
      depth: ZGame.depthMd,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          ExcludeSemantics(
            child: SvgPicture.string(
              '<svg viewBox="0 0 22 20"><rect x="2" y="7" width="18" height="11" rx="2.5" fill="${svgHex(z.teal)}" stroke="${svgHex(context.zs.outline)}" stroke-width="2"/><rect x="1" y="2" width="20" height="7" rx="3" fill="${svgHex(z.teal)}" stroke="${svgHex(context.zs.outline)}" stroke-width="2"/><rect x="9" y="2" width="4" height="16" fill="${svgHex(z.surface)}" stroke="${svgHex(context.zs.outline)}" stroke-width="1.6"/></svg>',
              width: 34,
              height: 30,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZTypography.button.copyWith(
                    fontSize: 14,
                    height: 1.3,
                    color: onAmber,
                  ),
                ),
                if (failed)
                  Text('کد دعوت بارگذاری نشد', style: sub)
                else if (!ready)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 96,
                      height: 12,
                      decoration: BoxDecoration(
                        color: onAmber.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                else
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'کد تو: '),
                        // A friend types this code: left-to-right, isolated from
                        // the Persian around it, characters left as they are.
                        TextSpan(
                          text: '\u2066${state.code}\u2069',
                          style: const TextStyle(letterSpacing: 1),
                        ),
                      ],
                    ),
                    style: sub,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!ready && !failed)
            const SizedBox(width: 64, height: 50)
          else
            _ShareButton(
              label: failed ? 'تلاش دوباره' : 'هم‌رسانی',
              semanticLabel:
                  failed ? 'بارگذاری دوبارهٔ کد دعوت' : 'هم‌رسانی کد دعوت',
              onTap: failed ? onRetry : onShare,
            ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  const _ShareButton({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyPressable(
        depth: ZGame.depthSm,
        onTap: onTap,
        semanticLabel: semanticLabel,
        builder:
            (context, depth, _) => ChunkyBox(
              fill: z.surface,
              depth: depth,
              radius: 12,
              highlight: false,
              borderWidth: ZGame.outlineInner,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                style: ZTypography.button.copyWith(
                  fontSize: 13,
                  height: 1,
                  color: z.ink,
                ),
              ),
            ),
      ),
    );
  }
}
