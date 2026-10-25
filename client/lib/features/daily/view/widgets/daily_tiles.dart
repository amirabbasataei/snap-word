import 'package:flutter/material.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/theme/app_typography.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/core/utils/persian_digits.dart';
import 'package:wordchain/core/widgets/chunky.dart';
import 'package:wordchain/features/daily/view/widgets/daily_format.dart';
import 'package:wordchain/features/daily/view/widgets/daily_icons.dart';

/// The two tiles under the chain (canvas `ZDailyAfterA`): the streak on amber
/// and the time left to the next challenge on indigo. With no streak the
/// countdown takes the whole row.
class DailyInfoTiles extends StatelessWidget {
  final int streak;

  /// The longest streak this device knows (0 = unknown).
  final int record;
  final DateTime now;

  const DailyInfoTiles({
    super.key,
    required this.streak,
    required this.record,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (streak > 0) ...[
              Expanded(child: _StreakTile(streak: streak, record: record)),
              const SizedBox(width: 10),
            ],
            Expanded(child: _NextTile(now: now)),
          ],
        ),
      ),
    );
  }
}

class _StreakTile extends StatelessWidget {
  final int streak;
  final int record;

  const _StreakTile({required this.streak, required this.record});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final title = '${toPersianDigits(streak)} روز پیاپی';
    // Any finished game counts for the day, so «امروز یکی اضافه شد» could be
    // false (a solo game earlier today already did it): say what is certain.
    final sub =
        record > streak
            ? 'رکورد: ${toPersianDigits(record)} روز'
            : 'امروز هم حساب شد';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$title، $sub',
      child: ChunkyBox(
        fill: z.amber,
        deep: z.amberDeep,
        depth: 5,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            DailyIcons.flame(
              body: z.coral,
              core: z.surface,
              outline: context.zs.outline,
              width: 28,
              height: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: ZTypography.button.copyWith(
                      fontSize: 16,
                      height: 1.2,
                      color: z.onAmber,
                    ),
                  ),
                  Text(
                    sub,
                    style: ZTypography.metaLabel.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                      color: z.onAmber,
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

class _NextTile extends StatelessWidget {
  final DateTime now;

  const _NextTile({required this.now});

  @override
  Widget build(BuildContext context) {
    final z = context.z;
    final left = untilIranMidnight(now);
    TextStyle meta() => ZTypography.metaLabel.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      height: 1.3,
      color: z.onIndigo,
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'چالش بعدی فردا ساعت ۰۰:۰۰، ${formatCountdownFa(left)} مانده',
      child: ChunkyBox(
        fill: z.indigo,
        deep: z.indigoDeep,
        depth: 5,
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('چالش بعدی · فردا ${toPersianDigits('00:00')}', style: meta()),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                dailyClockLabel(left),
                style: ZTypography.display.copyWith(
                  fontSize: 22,
                  height: 1.1,
                  color: z.onIndigo,
                ),
              ),
            ),
            Text('ساعت و دقیقه تا چالشی تازه', style: meta()),
          ],
        ),
      ),
    );
  }
}
