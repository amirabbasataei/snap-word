import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// A row of day chips marking a streak, labelled with the Persian weekday
/// initial (شنبه..جمعه) for each of the trailing [totalDays] calendar days
/// ending today. A day is "done" when it falls within the trailing
/// [streakCount]-day run ending at [lastPlayedDate] — filled `teal`; other
/// days (typically just today, still pending) render as an outlined `paper`
/// chip. Per the design token sheet these chips carry no offset shadow.
class StreakStrip extends StatelessWidget {
  final int totalDays;
  final int streakCount;
  final DateTime? lastPlayedDate;

  const StreakStrip({
    super.key,
    this.totalDays = 7,
    required this.streakCount,
    this.lastPlayedDate,
  });

  // Persian week starts Saturday: ش ی د س چ پ ج, indexed by Dart's
  // DateTime.weekday (Mon=1..Sun=7).
  static const _labels = ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];

  static String _labelFor(DateTime day) => _labels[day.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = lastPlayedDate == null
        ? null
        : DateTime(
            lastPlayedDate!.year, lastPlayedDate!.month, lastPlayedDate!.day);

    return Row(
      children: List.generate(totalDays, (i) {
        final day = today.subtract(Duration(days: totalDays - 1 - i));
        final done = last != null &&
            !day.isAfter(last) &&
            last.difference(day).inDays < streakCount;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: i == totalDays - 1 ? 0 : ZSpacing.sm / 2,
              right: i == 0 ? 0 : ZSpacing.sm / 2,
            ),
            child: Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? z.teal : z.paper,
                borderRadius: BorderRadius.circular(ZRadius.tileMin + 1),
                border: done ? null : Border.all(color: z.line, width: 1.5),
              ),
              child: Text(
                _labelFor(day),
                style: ZTypography.metaLabel.copyWith(
                  color: done ? z.onTeal : z.ink40,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
