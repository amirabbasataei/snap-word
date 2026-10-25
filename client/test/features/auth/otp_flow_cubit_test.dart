import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/auth/cubit/otp_flow_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

import 'auth_fakes.dart';

OtpFlowCubit build(
  FakeAuth auth,
  TestClock clock, {
  int cooldown = 120,
  int? expires = 120,
}) => OtpFlowCubit(
  authCubit: auth,
  phone: '09364419970',
  initialCooldownSeconds: cooldown,
  initialExpiresSeconds: expires,
  clock: clock.now,
);

void main() {
  late FakeAuth auth;
  late TestClock clock;

  setUp(() {
    auth = FakeAuth();
    clock = TestClock();
  });
  tearDown(() => auth.dispose());

  group('countdown', () {
    testWidgets('starts at the server cooldown and ticks down', (tester) async {
      final cubit = build(auth, clock);
      expect(cubit.state.cooldownSecondsRemaining, 120);
      expect(cubit.state.canResend, isFalse);

      await clock.advance(tester, 1);
      expect(cubit.state.cooldownSecondsRemaining, 119);
      await clock.advance(tester, 59);
      expect(cubit.state.cooldownSecondsRemaining, 60);
      await cubit.close();
    });

    testWidgets('is read from the clock, so a paused app catches up', (
      tester,
    ) async {
      final cubit = build(auth, clock);
      // Ninety seconds pass while timers are frozen (app in the background);
      // the first tick after resuming must show the real time left.
      clock.elapsed += const Duration(seconds: 90);
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.cooldownSecondsRemaining, 30);
      await cubit.close();
    });

    testWidgets('stops ticking once both deadlines have passed', (
      tester,
    ) async {
      final cubit = build(auth, clock, cooldown: 3, expires: 5);
      await clock.advance(tester, 3);
      expect(cubit.state.cooldownSecondsRemaining, 0);
      expect(cubit.state.canResend, isTrue);
      expect(cubit.state.codeExpired, isFalse);
      await clock.advance(tester, 2);
      expect(cubit.state.codeExpired, isTrue);
      // Nothing left to count: no timer may be pending when the test ends.
      expect(tester.binding.hasScheduledFrame, isFalse);
      await cubit.close();
    });

    testWidgets('a zero cooldown allows a resend and starts no timer', (
      tester,
    ) async {
      final cubit = build(auth, clock, cooldown: 0, expires: null);
      expect(cubit.state.canResend, isTrue);
      expect(cubit.state.codeExpired, isFalse);
      await cubit.close();
    });

    testWidgets('an unknown expiry never reads as expired', (tester) async {
      final cubit = build(auth, clock, cooldown: 2, expires: null);
      await clock.advance(tester, 10);
      expect(cubit.state.codeExpired, isFalse);
      await cubit.close();
    });

    testWidgets('rounds partial seconds up', (tester) async {
      final cubit = build(auth, clock, cooldown: 10);
      clock.elapsed += const Duration(milliseconds: 1500);
      await tester.pump(const Duration(seconds: 1));
      expect(cubit.state.cooldownSecondsRemaining, 9);
      await cubit.close();
    });

    testWidgets('closing the cubit cancels the timer', (tester) async {
      final cubit = build(auth, clock);
      await cubit.close();
      clock.elapsed += const Duration(seconds: 5);
      await tester.pump(const Duration(seconds: 5));
      expect(cubit.state.cooldownSecondsRemaining, 120);
    });
  });

  group('resend', () {
    testWidgets('does nothing while the cooldown runs', (tester) async {
      final cubit = build(auth, clock);
      await cubit.resend();
      expect(auth.sentTo, isEmpty);
      await cubit.close();
    });

    testWidgets('sends again once allowed and restarts both deadlines', (
      tester,
    ) async {
      auth.sendAnswers.add(
        const SendOtpResult(expiresInSeconds: 90, resendCooldownSeconds: 100),
      );
      final cubit = build(auth, clock, cooldown: 2);
      await clock.advance(tester, 2);
      expect(cubit.state.canResend, isTrue);

      final done = cubit.resend();
      expect(cubit.state.sendingResend, isTrue);
      expect(cubit.state.canResend, isFalse);
      await done;

      expect(auth.sentTo, ['09364419970']);
      expect(cubit.state.sendingResend, isFalse);
      expect(cubit.state.cooldownSecondsRemaining, 100);
      expect(cubit.state.codeExpired, isFalse);
      await clock.advance(tester, 1);
      expect(cubit.state.cooldownSecondsRemaining, 99);
      await cubit.close();
    });

    testWidgets('a second tap while sending is ignored', (tester) async {
      auth.sendGate = Completer();
      final cubit = build(auth, clock, cooldown: 0);
      final first = cubit.resend();
      await cubit.resend();
      expect(auth.sentTo.length, 1);
      auth.sendGate!.complete(defaultSend);
      await first;
      await cubit.close();
    });

    for (final code in ['resend_cooldown', 'rate_limited', 'invalid_phone']) {
      testWidgets('server error $code is shown and the pill stays usable', (
        tester,
      ) async {
        auth.sendAnswers.add(authError(code));
        final cubit = build(auth, clock, cooldown: 0);
        await cubit.resend();
        expect(cubit.state.errorCode, code);
        expect(cubit.state.sendingResend, isFalse);
        expect(cubit.state.canResend, isTrue);
        await cubit.close();
      });
    }

    testWidgets('a network failure is reported as network_error', (
      tester,
    ) async {
      auth.sendAnswers.add(const NetworkException('offline'));
      final cubit = build(auth, clock, cooldown: 0);
      await cubit.resend();
      expect(cubit.state.errorCode, 'network_error');
      expect(cubit.state.canResend, isTrue);
      await cubit.close();
    });

    testWidgets('a resend that finishes after close does not throw', (
      tester,
    ) async {
      auth.sendGate = Completer();
      final cubit = build(auth, clock, cooldown: 0);
      final pending = cubit.resend();
      await cubit.close();
      auth.sendGate!.complete(defaultSend);
      await pending;
    });
  });

  group('submit', () {
    test('success returns the result and ends the busy state', () async {
      auth.verifyAnswers.add(signedIn);
      final cubit = build(auth, clock, cooldown: 0);
      final r = await cubit.submit('1111', referralCode: 'K7M2QX');
      expect(r, same(signedIn));
      expect(cubit.state.submitting, isFalse);
      expect(cubit.state.hasError, isFalse);
      expect(auth.verifies.single, (
        phone: '09364419970',
        code: '1111',
        referral: 'K7M2QX',
      ));
      await cubit.close();
    });

    for (final code in [
      'invalid_code',
      'code_expired',
      'too_many_attempts',
      'otp_not_requested',
      'account_banned',
    ]) {
      test('$code comes back as null with the code in the state', () async {
        auth.verifyAnswers.add(authError(code));
        final cubit = build(auth, clock, cooldown: 0);
        expect(await cubit.submit('1234'), isNull);
        expect(cubit.state.errorCode, code);
        expect(cubit.state.errorMessage, 'server says $code');
        expect(cubit.state.submitting, isFalse);
        await cubit.close();
      });
    }

    test('a network failure is network_error', () async {
      auth.verifyAnswers.add(const NetworkException('offline'));
      final cubit = build(auth, clock, cooldown: 0);
      expect(await cubit.submit('1234'), isNull);
      expect(cubit.state.errorCode, 'network_error');
      await cubit.close();
    });

    test('the busy state is on while the request is in flight', () async {
      auth.verifyGate = Completer();
      final cubit = build(auth, clock, cooldown: 0);
      final pending = cubit.submit('1234');
      expect(cubit.state.submitting, isTrue);
      // A second submit while one is running is dropped.
      expect(await cubit.submit('1234'), isNull);
      expect(auth.verifies.length, 1);
      auth.verifyGate!.complete();
      await pending;
      expect(cubit.state.submitting, isFalse);
      await cubit.close();
    });

    test('a new attempt clears the previous error', () async {
      auth.verifyAnswers
        ..add(authError('invalid_code'))
        ..add(signedIn);
      final cubit = build(auth, clock, cooldown: 0);
      await cubit.submit('0000');
      expect(cubit.state.errorCode, 'invalid_code');
      await cubit.submit('1111');
      expect(cubit.state.hasError, isFalse);
      await cubit.close();
    });

    test('a result that arrives after close does not throw', () async {
      auth.verifyGate = Completer();
      final cubit = build(auth, clock, cooldown: 0);
      final pending = cubit.submit('1234');
      await cubit.close();
      auth.verifyGate!.complete();
      expect(await pending, isNotNull);
    });
  });

  test('clearError drops the error and only then emits', () async {
    auth.verifyAnswers.add(authError('invalid_code'));
    final cubit = build(auth, clock, cooldown: 0);
    await cubit.submit('0000');
    final seen = <OtpFlowState>[];
    final sub = cubit.stream.listen(seen.add);
    cubit.clearError();
    cubit.clearError();
    await Future<void>.delayed(Duration.zero);
    expect(seen.length, 1);
    expect(cubit.state.hasError, isFalse);
    await sub.cancel();
    await cubit.close();
  });
}
