import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';

/// The amber card under the header (canvas `ZAwards`): how many prizes wait
/// and, big at the end, that count.
///
/// The canvas's second line is «N از M جایزه گرفته‌ای» (claimed of all
/// awards). There is no catalogue of awards to count against, and claimed
/// prizes leave the list after a day, so the line shows what is real instead:
/// the coins waiting, or — with nothing to claim — a nudge.
class RewardsSummary extends StatelessWidget {
  final int ready;
  final int coins;

  /// Claimed prizes are still listed (they vanish a day after claiming).
  final bool anyClaimed;

  const RewardsSummary({
    super.key,
    required this.ready,
    required this.coins,
    required this.anyClaimed,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final headline =
        ready > 0 ? 'جایزه‌های آمادهٔ دریافت' : 'فعلاً جایزه‌ای آماده نیست';
    final sub =
        ready > 0
            ? 'روی هم ${formatPersianNumber(coins)} سکه منتظر توست'
            : anyClaimed
            ? 'همهٔ جایزه‌هایت را گرفته‌ای'
            : 'بازی کن تا جایزه‌ها برسند';
    return MergeSemantics(
      child: ChunkyBox(
        fill: z.amber,
        deep: z.amberDeep,
        depth: ZGame.depthMd,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: ZTypography.cardTitle.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                      color: z.onAmber,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: ZTypography.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                      color: z.onAmber,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                toPersianDigits(ready),
                style: ZTypography.display.copyWith(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  color: z.onAmber,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
