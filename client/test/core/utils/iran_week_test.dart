import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/iran_time.dart';

/// An instant given as Iran wall-clock time (UTC+03:30).
DateTime _iran(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, min, s).subtract(iranOffset);

void main() {
  // 2026-10-25 is a Sunday; the next Saturday is 2026-10-31.
  group('untilIranWeekReset', () {
    test('from Sunday afternoon: 5 days 8.5 hours to Saturday 00:00', () {
      expect(
        untilIranWeekReset(_iran(2026, 10, 25, 15, 30)),
        const Duration(days: 5, hours: 8, minutes: 30),
      );
    });

    test('Friday 23:59 is one minute from the reset', () {
      expect(
        untilIranWeekReset(_iran(2026, 10, 30, 23, 59)),
        const Duration(minutes: 1),
      );
    });

    test('Saturday 00:00 sharp (the reset minute) is a week away', () {
      expect(untilIranWeekReset(_iran(2026, 10, 31)), const Duration(days: 7));
    });

    test('Saturday later in the day: just under a week', () {
      expect(
        untilIranWeekReset(_iran(2026, 10, 31, 12)),
        const Duration(days: 6, hours: 12),
      );
    });

    test(
      'uses Iran time, not UTC: Friday 21:00 UTC is already Saturday 00:30',
      () {
        // 21:00 UTC + 3:30 = Saturday 00:30 in Iran.
        final now = DateTime.utc(2026, 10, 30, 21);
        expect(
          untilIranWeekReset(now),
          const Duration(days: 6, hours: 23, minutes: 30),
        );
      },
    );

    test('crosses a month and a year boundary', () {
      // Sunday 2027-01-03 → Saturday 2027-01-09.
      expect(untilIranWeekReset(_iran(2027, 1, 3)), const Duration(days: 6));
      expect(
        untilIranWeekReset(_iran(2026, 12, 31, 10)),
        // Thursday → Saturday 2027-01-02 00:00.
        const Duration(days: 1, hours: 14),
      );
    });
  });

  group('formatCountdownFa', () {
    test('days and hours', () {
      expect(
        formatCountdownFa(const Duration(days: 5, hours: 8, minutes: 30)),
        '۵ روز و ۸ ساعت',
      );
    });

    test('whole days drop the empty hours', () {
      expect(formatCountdownFa(const Duration(days: 7)), '۷ روز');
    });

    test('hours and minutes', () {
      expect(
        formatCountdownFa(const Duration(hours: 8, minutes: 30)),
        '۸ ساعت و ۳۰ دقیقه',
      );
    });

    test('whole hours drop the empty minutes', () {
      expect(formatCountdownFa(const Duration(hours: 3)), '۳ ساعت');
    });

    test('minutes only, never below one', () {
      expect(formatCountdownFa(const Duration(minutes: 20)), '۲۰ دقیقه');
      expect(formatCountdownFa(const Duration(seconds: 10)), '۱ دقیقه');
      expect(formatCountdownFa(Duration.zero), '۱ دقیقه');
    });
  });
}
