import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';

/// «سکهٔ رایگان»: the opt-in "watch an ad, get coins" card. The canvas draws
/// no such card, but the feature is real, so it keeps its place above the
/// prizes in the same card style.
class RewardsFreeCoinsCard extends StatelessWidget {
  final String body;
  final bool busy;
  final VoidCallback onWatch;

  const RewardsFreeCoinsCard({
    super.key,
    required this.body,
    required this.busy,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
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
          Text(
            'سکهٔ رایگان',
            style: ZTypography.cardTitle.copyWith(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              height: 1.35,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: ZTypography.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.55,
              color: z.ink60,
            ),
          ),
          const SizedBox(height: 10),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: ZDialogButton.primary(
              label: busy ? 'کمی صبر کن…' : 'دیدن تبلیغ',
              onTap: busy ? null : onWatch,
              accent: ZDialogAccent.amber,
              height: 44,
              radius: 14,
              depth: 4,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
