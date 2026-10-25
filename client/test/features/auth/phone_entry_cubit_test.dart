import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/auth/cubit/phone_entry_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';

import 'auth_fakes.dart';

const valid = '09364419970';

void main() {
  late FakeAuth auth;
  late DateTime now;
  late PhoneEntryCubit cubit;

  setUp(() {
    auth = FakeAuth();
    now = DateTime(2026, 10, 25, 12);
    cubit = PhoneEntryCubit(
      authCubit: auth,
      returnPath: '/friends',
      clock: () => now,
    );
  });
  tearDown(() async {
    await cubit.close();
    await auth.dispose();
  });

  group('phone validity', () {
    for (final (digits, ok) in [
      ('', false),
      ('09', false),
      ('0936441997', false),
      (valid, true),
      ('08364419970', false),
      ('093644199700', false),
    ]) {
      test('"$digits" is ${ok ? 'valid' : 'not valid'}', () {
        cubit.setDigits(digits);
        expect(cubit.state.phoneValid, ok);
        expect(cubit.state.canSubmit, ok);
      });
    }
  });

  test('submit with an incomplete number sends nothing', () async {
    cubit.setDigits('0936');
    expect(await cubit.submit(), isNull);
    expect(auth.sentTo, isEmpty);
    expect(cubit.state.hasError, isFalse);
  });

  test('success hands the OTP screen everything it needs', () async {
    auth.sendAnswers.add(
      const SendOtpResult(expiresInSeconds: 100, resendCooldownSeconds: 110),
    );
    cubit
      ..setDigits(valid)
      ..setReferralCode('K7M2QX');
    final args = await cubit.submit();
    expect(auth.sentTo, [valid]);
    expect(args!.phone, valid);
    expect(args.returnPath, '/friends');
    expect(args.referralCode, 'K7M2QX');
    expect(args.initialCooldownSeconds, 110);
    expect(args.initialExpiresSeconds, 100);
    expect(cubit.state.sending, isFalse);
    expect(cubit.state.hasError, isFalse);
  });

  test('no referral code stays null', () async {
    cubit.setDigits(valid);
    expect((await cubit.submit())!.referralCode, isNull);
  });

  test(
    'sending is on while the request is in flight, taps are dropped',
    () async {
      auth.sendGate = Completer();
      cubit.setDigits(valid);
      final first = cubit.submit();
      expect(cubit.state.sending, isTrue);
      expect(cubit.state.canSubmit, isFalse);
      expect(await cubit.submit(), isNull);
      expect(auth.sentTo.length, 1);
      auth.sendGate!.complete(defaultSend);
      await first;
      expect(cubit.state.sending, isFalse);
    },
  );

  for (final code in [
    'invalid_phone',
    'rate_limited',
    'validation_error',
    'internal_error',
  ]) {
    test('$code stays on the screen with the code in the state', () async {
      auth.sendAnswers.add(authError(code));
      cubit.setDigits(valid);
      expect(await cubit.submit(), isNull);
      expect(cubit.state.errorCode, code);
      expect(cubit.state.errorMessage, 'server says $code');
      expect(cubit.state.sending, isFalse);
      expect(cubit.state.canSubmit, isTrue);
    });
  }

  test('a network failure is network_error', () async {
    auth.sendAnswers.add(const NetworkException('offline'));
    cubit.setDigits(valid);
    expect(await cubit.submit(), isNull);
    expect(cubit.state.errorCode, 'network_error');
  });

  test('typing clears the error', () async {
    auth.sendAnswers.add(authError('invalid_phone'));
    cubit.setDigits(valid);
    await cubit.submit();
    expect(cubit.state.hasError, isTrue);
    cubit.setDigits('0936');
    expect(cubit.state.hasError, isFalse);
  });

  group('same number again within the cooldown', () {
    test('goes on to the OTP page with the time that is left', () async {
      cubit.setDigits(valid);
      await cubit.submit();
      now = now.add(const Duration(seconds: 50));
      auth.sendAnswers.add(authError('resend_cooldown'));
      final args = await cubit.submit();
      expect(args, isNotNull);
      expect(args!.phone, valid);
      expect(args.initialCooldownSeconds, 70);
      expect(args.initialExpiresSeconds, 70);
      expect(cubit.state.hasError, isFalse);
    });

    test(
      'an expired code has no time left: expiry is 0 not negative',
      () async {
        auth.sendAnswers.add(
          const SendOtpResult(expiresInSeconds: 30, resendCooldownSeconds: 120),
        );
        cubit.setDigits(valid);
        await cubit.submit();
        now = now.add(const Duration(seconds: 50));
        auth.sendAnswers
          ..clear()
          ..add(authError('resend_cooldown'));
        final args = await cubit.submit();
        expect(args!.initialCooldownSeconds, 70);
        expect(args.initialExpiresSeconds, 0);
      },
    );

    test('a number this screen never sent to shows the error', () async {
      auth.sendAnswers.add(authError('resend_cooldown'));
      cubit.setDigits(valid);
      expect(await cubit.submit(), isNull);
      expect(cubit.state.errorCode, 'resend_cooldown');
    });

    test('another number is not covered by the record', () async {
      cubit.setDigits(valid);
      await cubit.submit();
      auth.sendAnswers.add(authError('resend_cooldown'));
      cubit.setDigits('09121234567');
      expect(await cubit.submit(), isNull);
      expect(cubit.state.errorCode, 'resend_cooldown');
    });

    test('once the cooldown has passed the server error is shown', () async {
      cubit.setDigits(valid);
      await cubit.submit();
      now = now.add(const Duration(seconds: 125));
      auth.sendAnswers.add(authError('resend_cooldown'));
      expect(await cubit.submit(), isNull);
      expect(cubit.state.errorCode, 'resend_cooldown');
    });
  });

  test('a request that finishes after close does not throw', () async {
    auth.sendGate = Completer();
    cubit.setDigits(valid);
    final pending = cubit.submit();
    await cubit.close();
    auth.sendGate!.complete(defaultSend);
    expect(await pending, isNotNull);
  });
}
