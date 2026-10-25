import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';

/// A short, true statement of what the visible board counts — and, where the
/// server really has one, its prizes and clock: the weekly reset (Saturday
/// 00:00 Iran time) and the Daily Challenge's midnight. Not in the canvas;
/// derived from `config` (prize amounts, scheduler) so the tabs can't be
/// mistaken for each other (daily scores do **not** reach the weekly or
/// all-time boards — todo.md 2.4).
class BoardNote extends StatelessWidget {
  final BoardTab tab;

  /// The Daily Challenge number (daily tab only).
  final int? dayNumber;
  final DateTime now;

  const BoardNote({
    super.key,
    required this.tab,
    required this.now,
    this.dayNumber,
  });

  static String prizeLine(List<int> coins) =>
      'جایزهٔ سه نفر اول: ${coins.map(toPersianDigits).join(' · ')} سکه';

  /// The lines shown for [tab] at [now].
  static List<String> lines(
    BoardTab tab,
    DateTime now, {
    int? dayNumber,
  }) => switch (tab) {
    BoardTab.weekly => [
      prizeLine(GameConstants.weeklyPrizeCoins),
      'جدول تا ${formatCountdownFa(untilIranWeekReset(now))} دیگر بازنشانی می‌شود',
    ],
    BoardTab.daily => [
      dayNumber == null
          ? 'چالش روزانهٔ امروز'
          : 'چالش روزانهٔ شمارهٔ ${toPersianDigits(dayNumber)}',
      prizeLine(GameConstants.dailyPrizeCoins),
      'پایان امروز: ${formatCountdownFa(untilIranMidnight(now))} دیگر',
    ],
    BoardTab.allTime => ['مجموع امتیاز بازی‌های آنلاین'],
    BoardTab.friends => ['امتیاز این هفتهٔ تو و دوستانت'],
  };

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final text = lines(tab, now, dayNumber: dayNumber);
    return ChunkyBox(
      fill: z.surface,
      depth: 0,
      radius: 14,
      highlight: false,
      borderWidth: ZGame.outlineInner,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < text.length; i++)
              Text(
                text[i],
                textAlign: TextAlign.center,
                style: ZTypography.metaLabel.copyWith(
                  fontSize: 12,
                  fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w700,
                  height: 1.45,
                  color: i == 0 ? z.ink : z.ink60,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
