import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';

/// «مقایسهٔ دو تلاش» — the free attempt next to the paid one, the better score
/// marked (it is the one on the board). Not in the canvas; derived from its
/// cards.
class DailyCompareCard extends StatelessWidget {
  final DailyAttempt first;
  final DailyAttempt retry;

  const DailyCompareCard({super.key, required this.first, required this.retry});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final retryWins = retry.score > first.score;
    return ChunkyBox(
      fill: z.surface,
      depth: 5,
      radius: 22,
      highlight: false,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'مقایسهٔ دو تلاش',
            style: ZTypography.button.copyWith(
              fontSize: 13,
              height: 1.2,
              color: z.ink,
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Cell(
                    label: 'تلاش اول',
                    attempt: first,
                    best: !retryWins,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Cell(
                    label: 'تلاش دوباره',
                    attempt: retry,
                    best: retryWins,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final DailyAttempt attempt;
  final bool best;

  const _Cell({required this.label, required this.attempt, required this.best});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '$label: ${formatPersianNumber(attempt.score)} امتیاز، '
          '${toPersianDigits(attempt.chainLength)} کلمه${best ? '، بهترین' : ''}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: best ? z.tintTeal : z.wash,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              best ? '$label · بهترین' : label,
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: z.ink60,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                formatPersianNumber(attempt.score),
                style: ZTypography.display.copyWith(
                  fontSize: 20,
                  height: 1.2,
                  color: z.ink,
                ),
              ),
            ),
            Text(
              '${toPersianDigits(attempt.chainLength)} کلمه',
              style: ZTypography.metaLabel.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: z.ink60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
