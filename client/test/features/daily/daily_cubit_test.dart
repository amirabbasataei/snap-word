import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/daily/cubit/daily_cubit.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';

import 'daily_fakes.dart';

const _noCoins = DailyException(
  code: 'insufficient_coins',
  message: 'سکهٔ کافی نداری',
);

/// Records every state the cubit emits.
List<DailyState> _record(DailyCubit cubit) {
  final seen = <DailyState>[];
  cubit.stream.listen(seen.add);
  return seen;
}

void main() {
  group('load', () {
    test('not played → DailyAvailable, played → DailyAttempted', () async {
      final repo = FakeDailyRepo(dailyChallenge());
      final cubit = DailyCubit(repository: repo);
      final seen = _record(cubit);
      await cubit.load();
      repo.challenge = dailyChallenge(played: true);
      await cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((s) => s.runtimeType).toList(), [
        DailyLoading,
        DailyAvailable,
        DailyLoading,
        DailyAttempted,
      ]);
    });

    test('a failure becomes DailyError with the Persian message', () async {
      final repo = FakeDailyRepo(dailyChallenge())
        ..loadError = const DailyException(
          code: 'no_daily_challenge',
          message: 'چالش امروز هنوز آماده نشده',
        );
      final cubit = DailyCubit(repository: repo);
      await cubit.load();
      expect(
        cubit.state,
        const DailyError('no_daily_challenge', 'چالش امروز هنوز آماده نشده'),
      );
    });

    test('an unexpected exception gets the generic message', () async {
      final repo = FakeDailyRepo(dailyChallenge())..loadError = StateError('x');
      final cubit = DailyCubit(repository: repo);
      await cubit.load();
      expect(
        cubit.state,
        const DailyError(unknownErrorCode, loadDailyFailedMessage),
      );
    });

    test(
      'silent: no spinner while the screen is up, failure ignored',
      () async {
        final repo = FakeDailyRepo(dailyChallenge(played: true));
        final cubit = DailyCubit(repository: repo);
        await cubit.load();
        final seen = _record(cubit);
        await cubit.load(silent: true);
        repo.loadError = const DailyException(code: 'x', message: 'y');
        await cubit.load(silent: true);
        await Future<void>.delayed(Duration.zero);
        expect(seen.whereType<DailyLoading>(), isEmpty);
        expect(seen.whereType<DailyError>(), isEmpty);
        expect(cubit.state, isA<DailyAttempted>());
      },
    );

    test('silent with nothing on screen yet still shows the spinner', () async {
      final repo = FakeDailyRepo(dailyChallenge());
      final cubit = DailyCubit(repository: repo);
      final seen = _record(cubit);
      await cubit.load(silent: true);
      await Future<void>.delayed(Duration.zero);
      expect(seen.first, isA<DailyLoading>());
    });
  });

  group('refreshIfStale (back from the background)', () {
    // Iran date: 2026-10-16 15:30.
    final sameDay = DateTime.utc(2026, 10, 16, 12);
    // 2026-10-17 00:30 in Iran, still 2026-10-16 in UTC.
    final nextDay = DateTime.utc(2026, 10, 16, 21);

    test('the same Iran day: no call', () async {
      final repo = FakeDailyRepo(dailyChallenge());
      final cubit = DailyCubit(repository: repo);
      await cubit.load();
      await cubit.refreshIfStale(sameDay);
      expect(repo.loads, 1);
    });

    test('past Iran midnight: reloads quietly with the new day', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true));
      final cubit = DailyCubit(repository: repo);
      await cubit.load();
      repo.challenge = dailyChallenge(date: '2026-10-17', letter: 'س');
      final seen = _record(cubit);
      await cubit.refreshIfStale(nextDay);
      await Future<void>.delayed(Duration.zero);
      expect(repo.loads, 2);
      expect(seen.whereType<DailyLoading>(), isEmpty);
      expect(cubit.state, isA<DailyAvailable>());
      expect((cubit.state as DailyAvailable).challenge.startLetter, 'س');
    });

    test('nothing loaded, an error, or a retry in flight: no call', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true));
      final cubit = DailyCubit(repository: repo);
      await cubit.refreshIfStale(nextDay);
      expect(repo.loads, 0);

      await cubit.load();
      repo.retryGate = Completer();
      final pending = cubit.retry();
      await cubit.refreshIfStale(nextDay);
      expect(repo.loads, 1);
      repo.retryGate!.complete();
      await pending;
    });
  });

  group('retry', () {
    Future<DailyCubit> played(FakeDailyRepo repo) async {
      final cubit = DailyCubit(repository: repo);
      await cubit.load();
      return cubit;
    }

    test('success → busy, then DailyRetryAvailable', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true));
      final cubit = await played(repo);
      final seen = _record(cubit);
      await cubit.retry();
      await Future<void>.delayed(Duration.zero);
      expect(seen.map((s) => s.runtimeType).toList(), [
        DailyAttempted,
        DailyRetryAvailable,
      ]);
      expect((seen.first as DailyAttempted).retrying, isTrue);
      expect(seen.whereType<DailyLoading>(), isEmpty, reason: 'no spinner');
      expect(repo.retries, 1);
    });

    test(
      'a coin shortfall is a one-shot event, then back to the result',
      () async {
        final repo = FakeDailyRepo(dailyChallenge(played: true))
          ..retryError = _noCoins;
        final cubit = await played(repo);
        final seen = _record(cubit);
        await cubit.retry();
        await Future<void>.delayed(Duration.zero);
        expect(seen.map((s) => s.runtimeType).toList(), [
          DailyAttempted, // busy
          DailyInsufficientCoins,
          DailyAttempted, // idle again
        ]);
        expect((seen.last as DailyAttempted).retrying, isFalse);
        // A second tap fires the event again.
        seen.clear();
        await cubit.retry();
        await Future<void>.delayed(Duration.zero);
        expect(seen.whereType<DailyInsufficientCoins>(), hasLength(1));
      },
    );

    test(
      'a slot bought earlier (409) goes on to the game without paying',
      () async {
        final repo = FakeDailyRepo(dailyChallenge(played: true))
          ..retryError = const DailyException(
            code: 'already_retried',
            message: 'تلاش دوبارهٔ امروز را قبلاً استفاده کرده‌ای',
          );
        final cubit = await played(repo);
        await cubit.retry();
        expect(cubit.state, isA<DailyRetryAvailable>());
      },
    );

    test('another failure keeps the result and carries the message', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true))
        ..retryError = const DailyException(
          code: 'network',
          message: 'اتصال برقرار نشد',
        );
      final cubit = await played(repo);
      final seen = _record(cubit);
      await cubit.retry();
      await Future<void>.delayed(Duration.zero);
      final failed = seen.whereType<DailyRetryFailed>().single;
      expect(failed.message, 'اتصال برقرار نشد');
      expect(cubit.state, isA<DailyAttempted>());
      expect(cubit.state, isNot(isA<DailyRetryFailed>()));
    });

    test('an unexpected exception uses the generic retry message', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true))
        ..retryError = StateError('x');
      final cubit = await played(repo);
      final seen = _record(cubit);
      await cubit.retry();
      await Future<void>.delayed(Duration.zero);
      expect(
        seen.whereType<DailyRetryFailed>().single.message,
        dailyRetryFailedMessage,
      );
    });

    test('taps while the purchase is in flight are ignored', () async {
      final repo = FakeDailyRepo(dailyChallenge(played: true));
      final cubit = await played(repo);
      repo.retryGate = Completer();
      final first = cubit.retry();
      await cubit.retry();
      await cubit.retry();
      expect(repo.retries, 1);
      repo.retryGate!.complete();
      await first;
      expect(cubit.state, isA<DailyRetryAvailable>());
    });

    test('before the first attempt there is nothing to retry', () async {
      final repo = FakeDailyRepo(dailyChallenge());
      final cubit = await played(repo);
      await cubit.retry();
      expect(repo.retries, 0);
      expect(cubit.state, isA<DailyAvailable>());
    });
  });
}
