import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/friends/cubit/invite_code_cubit.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// «دوستت رو بیار، ۵۰ سکه بگیر» (canvas `ZProfileA`, indigo card): the
/// player's own referral code and a share button.
///
/// Real data only: the code is `GET /referral/me` (6 letters/digits, shown
/// left-to-right and never digit-converted so a friend can type it); «۵۰»
/// is the inviter reward the server grants per invited user
/// (`config.CoinReferralInviter`) and «۱۰۰» the new user's signup bonus. The
/// canvas's «۳ دعوت موفق» counter and its 5-step progress to a prize chest
/// have no endpoint (the server keeps no invite count, no chest), so they are
/// not drawn. Tapping the code copies it.
class ProfileInviteCard extends StatelessWidget {
  final InviteCodeState state;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onRetry;

  const ProfileInviteCard({
    super.key,
    required this.state,
    required this.onShare,
    required this.onCopy,
    required this.onRetry,
  });

  static const title = 'دوستت رو بیار، ۵۰ سکه بگیر';
  static const subtitle = 'دوستت ۱۰۰ سکه می‌گیرد و تو ۵۰ سکه';

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final ready = state.status == InviteCodeStatus.ready;
    final failed = state.status == InviteCodeStatus.failed;
    final sub = ZTypography.button.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 1.4,
      color: z.onIndigo,
    );
    return ChunkyBox(
      fill: z.indigo,
      deep: z.indigoDeep,
      depth: ZGame.depthMd,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: ZTypography.button.copyWith(
                fontSize: 15,
                height: 1.3,
                color: z.onIndigo,
              ),
            ),
          ),
          Text(subtitle, style: sub),
          const SizedBox(height: 8),
          if (failed)
            Row(
              children: [
                Expanded(child: Text('کد دعوت بارگذاری نشد', style: sub)),
                const SizedBox(width: 8),
                ProfileChunkButton(
                  label: 'تلاش دوباره',
                  semanticLabel: 'بارگذاری دوبارهٔ کد دعوت',
                  onTap: onRetry,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child:
                      ready
                          ? _CodeChip(code: state.code!, onCopy: onCopy)
                          : const _CodeSkeleton(),
                ),
                const SizedBox(width: 8),
                if (ready)
                  ProfileGlyphButton(
                    semanticLabel: 'هم‌رسانی کد دعوت',
                    onTap: onShare,
                    svg: shareSvg,
                    glyph: 18,
                  )
                else
                  const SizedBox(width: 44, height: 44),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;

  const _CodeChip({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCopy,
        child: Semantics(
          button: true,
          label: 'کپی کد دعوت',
          value: code.split('').join(' '),
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: ZGame.depthSm),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: z.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.zs.outline,
                  width: ZGame.outlineInner,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '\u2066$code\u2069',
                  maxLines: 1,
                  style: ZTypography.button.copyWith(
                    fontSize: 18,
                    letterSpacing: 3,
                    color: z.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeSkeleton extends StatelessWidget {
  const _CodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZGame.depthSm),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.z.onIndigo.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
