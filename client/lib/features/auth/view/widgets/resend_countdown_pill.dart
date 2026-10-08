import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';

String _formatCountdown(int seconds) {
  final s = seconds.clamp(0, 5999);
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return toPersianDigits('$mm:$ss');
}

/// The "⊙ ارسال دوباره تا ۰۲:۰۰" row from ZOtp.dc.html. Once the cooldown
/// reaches zero, the pill becomes a tappable "ارسال دوباره".
class ResendCountdownRow extends StatelessWidget {
  final int secondsRemaining;
  final bool sending;
  final VoidCallback onResend;

  const ResendCountdownRow({
    super.key,
    required this.secondsRemaining,
    required this.sending,
    required this.onResend,
  });

  bool get _canResend => secondsRemaining <= 0 && !sending;

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Row(
      children: [
        GestureDetector(
          onTap: _canResend ? onResend : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: z.surface,
              border: Border.all(color: z.line),
              borderRadius: BorderRadius.circular(ZRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: z.amber, width: 3),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Text(
                  _canResend
                      ? 'ارسال دوباره'
                      : 'ارسال دوباره تا ${_formatCountdown(secondsRemaining)}',
                  style: ZTypography.metaLabel.copyWith(
                    color: z.ink60,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
