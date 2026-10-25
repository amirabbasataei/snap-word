import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/features/daily/view/widgets/daily_icons.dart';

/// The streak card of the pre-game screen (canvas `ZDailyBeforeA`): the flame,
/// «N روز پیاپی» and the week's seven days. The canvas' «دیروز: ۲۱ کلمه» is not
/// drawn (the server keeps no per-day history); the record, when the device
/// knows one, stands in its place.
class DailyStreakCard extends StatelessWidget {
  final int streak;
  final int record;
  final DateTime? lastPlayed;
  final DateTime today;

  const DailyStreakCard({
    super.key,
    required this.streak,
    required this.record,
    required this.lastPlayed,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final title = '${toPersianDigits(streak)} روز پیاپی';
    final head = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DailyIcons.flame(body: z.coral, core: z.amber, outline: zs.outline),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: ZTypography.button.copyWith(
                  fontSize: 14,
                  height: 1.2,
                  color: z.ink,
                ),
              ),
              if (record > 0)
                Text(
                  'رکورد: ${toPersianDigits(record)} روز',
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
      ],
    );
    final strip = DailyWeekStrip(
      streak: streak,
      lastPlayed: lastPlayed,
      today: today,
    );
    return Semantics(
      container: true,
      label:
          '$title${record > 0 ? '، رکورد ${toPersianDigits(record)} روز' : ''}',
      child: ChunkyBox(
        fill: z.surface,
        depth: 4,
        radius: 18,
        highlight: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, c) {
            // The seven circles need 186dp next to ~120dp of text; below that (or
            // with big text) the strip drops under it.
            final inline = c.maxWidth >= 314 && scale <= 1.15;
            if (!inline) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [head, const SizedBox(height: 8), strip],
              );
            }
            return Row(
              children: [
                Expanded(child: head),
                const SizedBox(width: 8),
                strip,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The seven days of the Persian week (شنبه … جمعه, Saturday at the start): a
/// day in the trailing [streak]-day run ending at [lastPlayed] is teal, today
/// while still pending is amber, the rest are empty. Computed from the dates
/// it is given — nothing ticks.
class DailyWeekStrip extends StatelessWidget {
  final int streak;
  final DateTime? lastPlayed;
  final DateTime today;

  const DailyWeekStrip({
    super.key,
    required this.streak,
    required this.lastPlayed,
    required this.today,
  });

  // Indexed by DateTime.weekday (Mon = 1 … Sun = 7).
  static const _labels = ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];

  /// Whether [day] counts as played.
  static bool isDone(DateTime day, DateTime? lastPlayed, int streak) {
    if (lastPlayed == null) return false;
    final last = DateTime(lastPlayed.year, lastPlayed.month, lastPlayed.day);
    return !day.isAfter(last) && last.difference(day).inDays < streak;
  }

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final zs = context.zs;
    final now = DateTime(today.year, today.month, today.day);
    final start = now.subtract(Duration(days: (now.weekday + 1) % 7));
    return ExcludeSemantics(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Builder(
                builder: (context) {
                  final day = DateTime(start.year, start.month, start.day + i);
                  final done = isDone(day, lastPlayed, streak);
                  final pending = !done && day == now;
                  final (fill, on) =
                      done
                          ? (z.teal, z.onTeal)
                          : pending
                          ? (z.amber, z.onAmber)
                          : (z.wash, z.ink60);
                  return Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: zs.outline,
                        width: ZGame.outlineInner,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _labels[day.weekday - 1],
                        style: ZTypography.button.copyWith(
                          fontSize: 12,
                          height: 1,
                          color: on,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
