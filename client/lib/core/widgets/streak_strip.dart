import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_spacing.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';

/// A row of day chips for the current Persian week (شنبه..جمعه), Saturday at
/// the start (right in RTL) and Friday at the end. A day is "done" when it falls within the trailing
/// [streakCount]-day run ending at [lastPlayedDate] — filled `teal`; other
/// days (today if pending, and days still to come) render as an outlined `paper`
/// chip. Per the design token sheet these chips carry no offset shadow.
class StreakStrip extends StatelessWidget {
  static const totalDays = 7;
  final int streakCount;
  final DateTime? lastPlayedDate;

  const StreakStrip({
    super.key,
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
    final last =
        lastPlayedDate == null
            ? null
            : DateTime(
              lastPlayedDate!.year,
              lastPlayedDate!.month,
              lastPlayedDate!.day,
            );

    // Most recent Saturday (weekday 6) on or before today.
    final weekStart = today.subtract(Duration(days: (today.weekday + 1) % 7));

    return Row(
      children: List.generate(totalDays, (i) {
        final day = weekStart.add(Duration(days: i));
        final done =
            last != null &&
            !day.isAfter(last) &&
            last.difference(day).inDays < streakCount;
        return Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: i == totalDays - 1 ? 0 : ZSpacing.sm / 2,
              start: i == 0 ? 0 : ZSpacing.sm / 2,
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
