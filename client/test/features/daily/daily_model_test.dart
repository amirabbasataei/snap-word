import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';
import 'package:wordchain/features/daily/view/widgets/daily_format.dart';
import 'package:wordchain/features/daily/view/widgets/daily_streak.dart';

import 'daily_fakes.dart';

void main() {
  group('DailyChallenge', () {
    test('no attempt: nothing to show or retry', () {
      final c = dailyChallenge();
      expect(c.hasAttempted, isFalse);
      expect(c.bestAttempt, isNull);
      expect(c.canRetry, isFalse);
    });

    test('one attempt: it is the best, and the retry is on offer', () {
      final c = dailyChallenge(played: true);
      expect(c.bestAttempt!.attemptNumber, 1);
      expect(c.canRetry, isTrue);
    });

    test('a better retry replaces the first as the best', () {
      final c = dailyChallenge(
        attempt: dailyAttempt(score: 300),
        retry: dailyAttempt(number: 2, score: 520),
      );
      expect(c.bestAttempt!.score, 520);
      expect(c.canRetry, isFalse);
    });

    test('a worse retry does not — the server ranks the best score', () {
      final c = dailyChallenge(
        attempt: dailyAttempt(score: 460),
        retry: dailyAttempt(number: 2, score: 300),
      );
      expect(c.bestAttempt!.attemptNumber, 1);
      expect(c.bestAttempt!.score, 460);
    });

    test('a tie keeps the first attempt', () {
      final c = dailyChallenge(
        attempt: dailyAttempt(score: 400),
        retry: dailyAttempt(number: 2, score: 400),
      );
      expect(c.bestAttempt!.attemptNumber, 1);
    });

    test('fromJson reads what GET /daily sends', () {
      final c = DailyChallenge.fromJson({
        'challenge_date': '2026-10-16',
        'day_number': 42,
        'start_letter': 'ب',
        'today_best': 460,
        'your_best': 300,
        'daily_streak': 7,
        'attempt': {
          'attempt_number': 1,
          'score': 300,
          'chain_length': 2,
          'word_chain': ['بادام', 'مداد'],
        },
        'retry_attempt': null,
        'rank': 3,
      });
      expect(c.startLetter, 'ب');
      expect(c.rank, 3);
      expect(c.attempt!.wordChain, ['بادام', 'مداد']);
      expect(c.retryAttempt, isNull);
    });
  });

  group('Iran date', () {
    test('iranDateString rolls over at 20:30 UTC', () {
      expect(iranDateString(DateTime.utc(2026, 10, 16, 20, 29)), '2026-10-16');
      expect(iranDateString(DateTime.utc(2026, 10, 16, 20, 30)), '2026-10-17');
      expect(iranDateString(DateTime.utc(2026, 12, 31, 21)), '2027-01-01');
    });

    test('dailyDateLabel: weekday + Jalali day and month', () {
      expect(dailyDateLabel('2026-10-16'), 'جمعه ۲۴ مهر');
      expect(dailyDateLabel('2026-10-17'), 'شنبه ۲۵ مهر');
      expect(dailyDateLabel('2026-03-21'), 'شنبه ۱ فروردین');
    });

    test('dailyDateLabel falls back to today in Iran', () {
      final now = DateTime.utc(2026, 10, 16, 21); // 00:30 on the 17th there
      expect(dailyDateLabel(null, now), 'شنبه ۲۵ مهر');
      expect(dailyDateLabel('garbage', now), 'شنبه ۲۵ مهر');
    });

    test('dailyClockLabel: hours:minutes, never negative', () {
      expect(dailyClockLabel(const Duration(hours: 8, minutes: 30)), '۰۸:۳۰');
      expect(dailyClockLabel(const Duration(minutes: 5)), '۰۰:۰۵');
      expect(dailyClockLabel(const Duration(seconds: 20)), '۰۰:۰۰');
      expect(dailyClockLabel(const Duration(seconds: -5)), '۰۰:۰۰');
    });
  });

  group('week strip', () {
    final today = DateTime(2026, 10, 16);

    test('a day inside the trailing run is done, older and later are not', () {
      // Streak 3 ending today (Fri 16): Wed 14, Thu 15, Fri 16.
      bool done(int d) =>
          DailyWeekStrip.isDone(DateTime(2026, 10, d), today, 3);
      expect(done(13), isFalse);
      expect(done(14), isTrue);
      expect(done(15), isTrue);
      expect(done(16), isTrue);
      expect(done(17), isFalse);
    });

    test('no last-played date: nothing is done', () {
      expect(DailyWeekStrip.isDone(today, null, 5), isFalse);
    });
  });
}
