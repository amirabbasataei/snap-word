import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/profile/view/widgets/profile_parts.dart';

/// «کلمه‌ای کم داریم؟»: suggest a word the game did not know (guests too — they
/// are only paid once signed in) and, for accounts, follow what became of the
/// earlier suggestions. The reward is `GameConstants.wordSuggestionCoins`.
class ProfileWordCard extends StatelessWidget {
  final bool signedIn;
  final VoidCallback onSuggest;
  final VoidCallback onMine;

  const ProfileWordCard({
    super.key,
    required this.signedIn,
    required this.onSuggest,
    required this.onMine,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return ChunkyBox(
      fill: z.surface,
      depth: ZGame.depthMd,
      radius: 20,
      highlight: false,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'کلمه‌ای کم داریم؟',
              style: ZTypography.button.copyWith(
                fontSize: 15,
                height: 1.3,
                color: z.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            signedIn
                ? 'کلمهٔ درستی که بازی نپذیرفت را بفرست؛ اگر تأیید شود ${toPersianDigits(GameConstants.wordSuggestionCoins)} سکه هدیه می‌گیری.'
                : 'کلمهٔ درستی که بازی نپذیرفت را بفرست. برای گرفتن جایزه باید وارد حساب باشی.',
            style: ZTypography.button.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.5,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ProfileChunkButton(
                  label: 'پیشنهاد کلمه',
                  primary: true,
                  onTap: onSuggest,
                ),
              ),
              if (signedIn) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ProfileChunkButton(
                    label: 'پیشنهادهای من',
                    onTap: onMine,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
