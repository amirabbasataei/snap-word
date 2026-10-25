import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// Subscription status (no canvas frame — derived from the token system, in
/// the slot the canvas gives its badges). Free: what the subscription really
/// unlocks and «اشتراک ویژه». Premium: the active-until date and
/// «تغییر آواتار».
///
/// The list names only perks that exist: quick messages in 1v1 and the
/// avatars + crown. The old card also promised «بدون تبلیغ» and «۲۰۰ سکه در
/// هفته»; the weekly grant is not built and ads are not switched off for
/// premium, so neither is claimed. Premium itself is granted server-side only
/// (`users.premium_until`).
class ProfilePremiumCard extends StatelessWidget {
  final PremiumPerks perks;
  final VoidCallback onChangeAvatar;
  final VoidCallback onSubscribe;

  const ProfilePremiumCard({
    super.key,
    required this.perks,
    required this.onChangeAvatar,
    required this.onSubscribe,
  });

  static const benefits = [
    'ارسال پیام‌های سریع حین بازی دو نفره',
    'آواتارهای ویژه و نشان تاج کنار نام',
  ];

  static String untilLabel(DateTime until) {
    final j = Jalali.fromDateTime(until.toLocal());
    return '${toPersianDigits(j.day)} ${j.formatter.mN} ${toPersianDigits(j.year)}';
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final premium = perks.isPremium;
    final until = perks.premiumUntil;
    return ProfileCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: ChunkyBox(
                  fill: z.amber,
                  depth: 0,
                  circle: true,
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: ProfileCrown(
                    size: 20,
                    fill: z.surface,
                    stroke: z.onAmber,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    premium ? 'اشتراک ویژه فعال است' : 'اشتراک ویژه',
                    style: ZTypography.button.copyWith(
                      fontSize: 15,
                      height: 1.3,
                      color: z.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (premium && until != null) ...[
            const SizedBox(height: 6),
            Text(
              'تا ${untilLabel(until)}',
              style: ZTypography.body.copyWith(
                fontWeight: FontWeight.w700,
                color: z.ink60,
              ),
            ),
          ] else if (!premium) ...[
            const SizedBox(height: 6),
            for (final b in benefits)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $b',
                  style: ZTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: z.ink60,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(bottom: ZGame.depthSm),
            child: ProfileChunkButton(
              label: premium ? 'تغییر آواتار' : 'اشتراک ویژه',
              primary: true,
              onTap: premium ? onChangeAvatar : onSubscribe,
            ),
          ),
        ],
      ),
    );
  }
}
