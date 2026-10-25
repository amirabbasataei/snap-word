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

String formatCountdown(int seconds) {
  final s = seconds.clamp(0, 5999);
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return toPersianDigits('$mm:$ss');
}

/// «ارسال دوباره تا ۰۰:۴۲» (canvas `ZOtpA`): a flat surface chip while the
/// server's resend cooldown runs, a pressable one once a new code may be
/// asked for. The voice-call chip of the canvas is not built — the backend
/// only sends SMS.
class ResendPill extends StatelessWidget {
  final int secondsRemaining;
  final bool sending;
  final VoidCallback onResend;

  const ResendPill({
    super.key,
    required this.secondsRemaining,
    required this.sending,
    required this.onResend,
  });

  bool get _ready => secondsRemaining <= 0 && !sending;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final String text;
    if (sending) {
      text = 'در حال ارسال…';
    } else if (secondsRemaining > 0) {
      text = 'ارسال دوباره تا ${formatCountdown(secondsRemaining)}';
    } else {
      text = 'ارسال دوباره';
    }
    final label = Text(
      text,
      maxLines: 1,
      style: ZTypography.button.copyWith(
        fontSize: 12.5,
        height: 1,
        color: _ready ? z.ink : z.ink60,
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyPressable(
        depth: ZGame.depthSm,
        onTap: _ready ? onResend : null,
        semanticLabel: text,
        builder:
            (context, depth, _) => ExcludeSemantics(
              child: ChunkyBox(
                fill: z.surface,
                depth: _ready ? depth : ZGame.depthSm,
                radius: 14,
                highlight: false,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(widthFactor: 1, child: label),
              ),
            ),
      ),
    );
  }
}

/// «تازه‌واردی؟» (canvas `ZOtpA`): the indigo card that says what a new
/// account gets. The amounts are the server's own constants; the referral
/// line appears only when a code was stashed on the phone screen.
class WelcomeCard extends StatelessWidget {
  final bool hasReferral;

  const WelcomeCard({super.key, required this.hasReferral});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final welcome = toPersianDigits(GameConstants.welcomeBonusCoins);
    final referral = toPersianDigits(GameConstants.referralSignupCoins);
    final body =
        hasReferral
            ? 'با همین کد حساب تازه‌ات ساخته می‌شود و $welcome سکهٔ خوش‌آمد، '
                'به‌علاوهٔ $referral سکه برای کد دعوتت می‌گیری.'
            : 'با همین کد حساب تازه‌ات ساخته می‌شود و $welcome سکهٔ خوش‌آمد می‌گیری.';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ChunkyBox(
        fill: z.indigo,
        deep: z.indigoDeep,
        depth: 4,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ExcludeSemantics(
              child: SvgPicture.string(
                '<svg viewBox="0 0 22 20"><rect x="2" y="7" width="18" height="11" rx="2.5" fill="${svgHex(z.amber)}" stroke="${svgHex(zs.outline)}" stroke-width="2"/><rect x="1" y="2" width="20" height="7" rx="3" fill="${svgHex(z.amber)}" stroke="${svgHex(zs.outline)}" stroke-width="2"/><rect x="9" y="2" width="4" height="16" fill="${svgHex(z.surface)}" stroke="${svgHex(zs.outline)}" stroke-width="1.6"/></svg>',
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
                    'تازه‌واردی؟',
                    style: ZTypography.display.copyWith(
                      fontSize: 14,
                      height: 1.3,
                      color: z.onIndigo,
                    ),
                  ),
                  Text(
                    body,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                      color: z.onIndigo,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short status line under the OTP boxes / phone field: a coral dot and the
/// message, announced to screen readers when it appears.
class AuthStatusLine extends StatelessWidget {
  final String message;

  const AuthStatusLine(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Semantics(
        liveRegion: true,
        label: message,
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: z.coral,
                  shape: BoxShape.circle,
                  border: Border.all(color: zs.outline, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                  color: zs.coralInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
