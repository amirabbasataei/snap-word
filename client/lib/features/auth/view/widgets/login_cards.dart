import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/chunky_pressable.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

/// The amber «کد دعوت داری؟» card under the phone card (canvas `ZPhoneA`).
/// A referral code is a sign-up gift (100 coins on a new number) or, entered
/// after login, a smaller one (50) — the sub-line says both because the
/// screen cannot know which kind of number this is.
class ReferralTeaser extends StatelessWidget {
  final String? code;
  final VoidCallback onTap;

  const ReferralTeaser({super.key, required this.code, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final has = code != null;
    final title = has ? 'کد دعوت ثبت شد' : 'کد دعوت داری؟';
    final sub =
        has
            ? 'برای عوض کردنش بزن'
            : 'با شمارهٔ تازه ${toPersianDigits(GameConstants.referralSignupCoins)} سکه، '
                'بعد از ورود ${toPersianDigits(GameConstants.referralRedeemCoins)} سکه';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyPressable(
        depth: 4,
        onTap: onTap,
        semanticLabel: '$title، $sub',
        builder:
            (context, depth, _) => ExcludeSemantics(
              child: ChunkyBox(
                fill: z.amber,
                deep: z.amberDeep,
                depth: depth,
                radius: 18,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: z.surface,
                        border: Border.all(color: zs.outline, width: 3),
                      ),
                      alignment: Alignment.center,
                      child:
                          has
                              ? SvgPicture.string(
                                '<svg viewBox="0 0 24 24" fill="none" stroke="${svgHex(z.ink)}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
                                width: 16,
                                height: 16,
                              )
                              : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  toPersianDigits(
                                    GameConstants.referralSignupCoins,
                                  ),
                                  style: ZTypography.display.copyWith(
                                    fontSize: 14,
                                    height: 1,
                                    color: z.ink,
                                  ),
                                ),
                              ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: ZTypography.display.copyWith(
                              fontSize: 14,
                              height: 1.3,
                              color: z.onAmber,
                            ),
                          ),
                          Text(
                            sub,
                            style: ZTypography.metaLabel.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                              color: z.onAmber,
                            ),
                          ),
                        ],
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

/// «فعلاً مهمان می‌مانم» with its caption, pinned to the bottom of the screen
/// (canvas `ZPhoneA`). Guests play solo and vs-AI with no account.
class GuestOption extends StatelessWidget {
  final VoidCallback onTap;

  const GuestOption({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChunkyPressable(
            depth: ZGame.depthSm,
            onTap: onTap,
            semanticLabel: 'فعلاً مهمان می‌مانم',
            builder:
                (context, depth, _) => ChunkyBox(
                  fill: z.surface,
                  depth: depth,
                  radius: 14,
                  highlight: false,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    widthFactor: 1,
                    child: ExcludeSemantics(
                      child: Text(
                        'فعلاً مهمان می‌مانم',
                        style: ZTypography.button.copyWith(
                          fontSize: 14,
                          height: 1,
                          color: z.ink,
                        ),
                      ),
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'امتیاز مهمان فقط روی این گوشی می‌ماند',
            textAlign: TextAlign.center,
            style: ZTypography.metaLabel.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.8,
              color: z.ink,
            ),
          ),
        ],
      ),
    );
  }
}
