import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/z_otp_verify_screen.dart';

import '../../helpers/contrast.dart';
import '../../helpers/z_test_app.dart';
import 'auth_fakes.dart';

late FakeAuth auth;
late TestClock clock;
late List<String> visited;

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpOtp(
  WidgetTester tester, {
  OtpVerifyArgs? args,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(393, 852),
  bool reduceMotion = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  visited = [];
  await tester.pumpWidget(
    loginApp(
      loginRouter(
        auth,
        initial: '/login/otp',
        extra: args ?? otpArgs(),
        clock: clock,
        visited: visited,
      ),
      brightness: brightness,
      textScale: textScale,
      reduceMotion: reduceMotion,
    ),
  );
  await flush(tester);
}

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await flush(tester);
}

Future<void> waitOutToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 1));
}

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

const _confirm = 'تأیید و ورود';

void main() {
  setUpAll(loadVazirmatn);
  setUp(() {
    auth = registerAuth();
    clock = TestClock();
  });
  tearDown(() async {
    await auth.dispose();
    unregisterAuth();
  });

  group('first look', () {
    testWidgets(
      'shows the canvas content and nothing the server does not back',
      (tester) async {
        await pumpOtp(tester);
        expect(find.text('تأیید شماره'), findsOneWidget);
        expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
        expect(find.text('فرستاده شد به'), findsOneWidget);
        expect(find.text('۰۹۳۶۴۴۱۹۹۷۰'), findsOneWidget);
        expect(find.text('ویرایش'), findsOneWidget);
        expect(find.text('ارسال دوباره تا ۰۲:۰۰'), findsOneWidget);
        expect(find.text('تازه‌واردی؟'), findsOneWidget);
        expect(
          find.text(
            'با همین کد حساب تازه‌ات ساخته می‌شود و ۵۰ سکهٔ خوش‌آمد می‌گیری.',
          ),
          findsOneWidget,
        );
        expect(find.text(_confirm), findsOneWidget);
        // The voice call, the SMS auto-read claim and the hand-drawn keypad of
        // the canvas are not built: nothing on the server or device backs them.
        for (final absent in ['تماس صوتی', 'خودکار', '⌫']) {
          expect(find.textContaining(absent), findsNothing, reason: absent);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a stashed referral code is mentioned with its real bonus', (
      tester,
    ) async {
      await pumpOtp(tester, args: otpArgs(referral: 'K7M2QX'));
      expect(
        find.text(
          'با همین کد حساب تازه‌ات ساخته می‌شود و ۵۰ سکهٔ خوش‌آمد، '
          'به‌علاوهٔ ۱۰۰ سکه برای کد دعوتت می‌گیری.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the number keyboard is up and the button waits for 4 digits', (
      tester,
    ) async {
      await pumpOtp(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tap(find.text(_confirm));
      await flush(tester);
      expect(auth.verifies, isEmpty);
    });
  });

  group('typing the code', () {
    testWidgets('each digit fills a box, in Persian digits', (tester) async {
      await pumpOtp(tester);
      await tester.enterText(find.byType(TextField), '4');
      await tester.pump();
      expect(find.text('۴'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '48');
      await tester.pump();
      expect(find.text('۴'), findsOneWidget);
      expect(find.text('۸'), findsOneWidget);
      expect(auth.verifies, isEmpty);
    });

    testWidgets(
      'Persian and Arabic digits are folded to ASCII; extras are cut',
      (tester) async {
        await pumpOtp(tester);
        await typeCode(tester, '۴٨1۲99');
        expect(auth.verifies.single.code, '4812');
        expect(auth.verifies.single.phone, '09364419970');
        expect(auth.verifies.single.referral, isNull);
      },
    );

    testWidgets('letters are ignored', (tester) async {
      await pumpOtp(tester);
      await typeCode(tester, 'a4b8');
      expect(fieldText(tester), '48');
      expect(auth.verifies, isEmpty);
    });

    testWidgets('the fourth digit submits at once, with the stashed referral', (
      tester,
    ) async {
      await pumpOtp(tester, args: otpArgs(referral: 'K7M2QX'));
      await typeCode(tester, '123');
      expect(auth.verifies, isEmpty);
      await typeCode(tester, '1234');
      expect(auth.verifies.single, (
        phone: '09364419970',
        code: '1234',
        referral: 'K7M2QX',
      ));
    });

    testWidgets('the button submits a full code as well', (tester) async {
      auth.verifyGate = Completer();
      await pumpOtp(tester);
      await typeCode(tester, '1111');
      auth.verifyGate!.complete();
      await flush(tester);
      expect(auth.verifies.length, 1);
    });

    testWidgets('while checking: the button waits, the field locks', (
      tester,
    ) async {
      auth.verifyGate = Completer();
      await pumpOtp(tester);
      await typeCode(tester, '1111');
      expect(find.text('در حال بررسی کد…'), findsOneWidget);
      expect(find.text(_confirm), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      await tester.tap(find.text('در حال بررسی کد…'));
      await flush(tester);
      expect(auth.verifies.length, 1);
      auth.verifyGate!.complete();
      await flush(tester);
      expect(find.text('page:home'), findsOneWidget);
    });
  });

  group('success', () {
    testWidgets('an existing account goes to Home', (tester) async {
      await pumpOtp(tester);
      await typeCode(tester, '1111');
      expect(find.text('page:home'), findsOneWidget);
      // No welcome toast for someone who already had an account.
      expect(find.textContaining('هدیه'), findsNothing);
    });

    testWidgets('…or to the page they came from, without passing Home', (
      tester,
    ) async {
      await pumpOtp(tester, args: otpArgs(returnPath: '/friends'));
      await typeCode(tester, '1111');
      expect(find.text('page:friends'), findsOneWidget);
      expect(visited, isNot(contains('/home')));
    });

    testWidgets('a new account hears about its welcome gift', (tester) async {
      auth.verifyAnswers.add(newcomer(coins: 50));
      await pumpOtp(tester);
      await typeCode(tester, '1111');
      expect(find.text('page:home'), findsOneWidget);
      expect(find.text('خوش آمدی! ۵۰ سکه هدیه گرفتی'), findsOneWidget);
      await waitOutToast(tester);
    });

    testWidgets('…with a valid referral code the whole balance is the gift', (
      tester,
    ) async {
      auth.verifyAnswers.add(newcomer(coins: 150));
      await pumpOtp(tester, args: otpArgs(referral: 'K7M2QX'));
      await typeCode(tester, '1111');
      expect(find.text('خوش آمدی! ۱۵۰ سکه هدیه گرفتی'), findsOneWidget);
      await waitOutToast(tester);
    });

    testWidgets(
      'a referral code that did not resolve is said so, not praised',
      (tester) async {
        auth.verifyAnswers.add(
          newcomer(coins: 50, referralWarning: 'referral_not_found'),
        );
        await pumpOtp(tester, args: otpArgs(referral: 'ZZZZZZ'));
        await typeCode(tester, '1111');
        expect(find.text(referralNotFoundAtSignupMessage), findsOneWidget);
        expect(find.textContaining('هدیه'), findsNothing);
        await waitOutToast(tester);
      },
    );

    testWidgets(
      'an existing account that stashed a code is told it is unused',
      (tester) async {
        await pumpOtp(tester, args: otpArgs(referral: 'K7M2QX'));
        await typeCode(tester, '1111');
        expect(find.text(referralNeedsNewAccountMessage), findsOneWidget);
        await waitOutToast(tester);
      },
    );
  });

  group('failures', () {
    for (final code in [
      'invalid_code',
      'code_expired',
      'too_many_attempts',
      'otp_not_requested',
      'account_banned',
    ]) {
      testWidgets('$code shows its Persian message and clears the boxes', (
        tester,
      ) async {
        auth.verifyAnswers.add(authError(code));
        await pumpOtp(tester);
        await typeCode(tester, '1234');
        expect(find.text(errorMessageFor(code)), findsOneWidget);
        expect(find.textContaining('server says'), findsNothing);
        expect(fieldText(tester), '');
        expect(find.text(_confirm), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(find.text('page:home'), findsNothing);
      });
    }

    testWidgets('a network failure says so and the code can be retyped', (
      tester,
    ) async {
      auth.verifyAnswers
        ..add(const NetworkException(networkErrorMessage))
        ..add(signedIn);
      await pumpOtp(tester);
      await typeCode(tester, '1234');
      expect(find.text(networkErrorMessage), findsOneWidget);
      await typeCode(tester, '1234');
      expect(auth.verifies.length, 2);
      expect(find.text('page:home'), findsOneWidget);
    });

    testWidgets('the message goes away as soon as the player types', (
      tester,
    ) async {
      auth.verifyAnswers.add(authError('invalid_code'));
      await pumpOtp(tester);
      await typeCode(tester, '1234');
      expect(find.text(errorMessageFor('invalid_code')), findsOneWidget);
      await typeCode(tester, '5');
      expect(find.text(errorMessageFor('invalid_code')), findsNothing);
    });

    testWidgets('a wrong code then the right one signs in', (tester) async {
      auth.verifyAnswers
        ..add(authError('invalid_code'))
        ..add(signedIn);
      await pumpOtp(tester);
      await typeCode(tester, '0000');
      await typeCode(tester, '1111');
      expect(auth.verifies.map((v) => v.code), ['0000', '1111']);
      expect(find.text('page:home'), findsOneWidget);
    });
  });

  group('resend', () {
    testWidgets('counts down from stored time, one second at a time', (
      tester,
    ) async {
      await pumpOtp(tester);
      await clock.advance(tester, 1);
      expect(find.text('ارسال دوباره تا ۰۱:۵۹'), findsOneWidget);
      await clock.advance(tester, 59);
      expect(find.text('ارسال دوباره تا ۰۱:۰۰'), findsOneWidget);
      await clock.advance(tester, 55);
      expect(find.text('ارسال دوباره تا ۰۰:۰۵'), findsOneWidget);
    });

    testWidgets('tapping the pill before it is ready does nothing', (
      tester,
    ) async {
      await pumpOtp(tester);
      await tester.tap(find.textContaining('ارسال دوباره تا'));
      await flush(tester);
      expect(auth.sentTo, isEmpty);
    });

    testWidgets('after the cooldown it sends again and starts over', (
      tester,
    ) async {
      await pumpOtp(tester, args: otpArgs(cooldown: 3, expires: 3));
      await clock.advance(tester, 3);
      expect(find.text('ارسال دوباره'), findsOneWidget);
      await tester.tap(find.text('ارسال دوباره'));
      await flush(tester);
      expect(auth.sentTo, ['09364419970']);
      expect(find.text('ارسال دوباره تا ۰۲:۰۰'), findsOneWidget);
      // The new code is valid again: no expiry notice.
      expect(find.text(errorMessageFor('code_expired')), findsNothing);
    });

    testWidgets('shows «در حال ارسال…» while the request is out', (
      tester,
    ) async {
      auth.sendGate = Completer();
      await pumpOtp(tester, args: otpArgs(cooldown: 1, expires: 1));
      await clock.advance(tester, 1);
      await tester.tap(find.text('ارسال دوباره'));
      await tester.pump();
      expect(find.text('در حال ارسال…'), findsOneWidget);
      await tester.tap(find.text('در حال ارسال…'));
      await tester.pump();
      expect(auth.sentTo.length, 1);
      auth.sendGate!.complete(defaultSend);
      await flush(tester);
      expect(find.text('ارسال دوباره تا ۰۲:۰۰'), findsOneWidget);
    });

    for (final code in ['rate_limited', 'resend_cooldown']) {
      testWidgets('a refused resend ($code) shows its message', (tester) async {
        auth.sendAnswers.add(authError(code));
        await pumpOtp(tester, args: otpArgs(cooldown: 1, expires: 1));
        await clock.advance(tester, 1);
        await tester.tap(find.text('ارسال دوباره'));
        await flush(tester);
        expect(find.text(errorMessageFor(code)), findsOneWidget);
        expect(find.text('ارسال دوباره'), findsOneWidget);
      });
    }

    testWidgets('a network failure on resend says so', (tester) async {
      auth.sendAnswers.add(const NetworkException(networkErrorMessage));
      await pumpOtp(tester, args: otpArgs(cooldown: 1, expires: 1));
      await clock.advance(tester, 1);
      await tester.tap(find.text('ارسال دوباره'));
      await flush(tester);
      expect(find.text(networkErrorMessage), findsOneWidget);
    });

    testWidgets('a code past its expiry is flagged without asking the server', (
      tester,
    ) async {
      await pumpOtp(tester, args: otpArgs(cooldown: 4, expires: 4));
      expect(find.text(errorMessageFor('code_expired')), findsNothing);
      await clock.advance(tester, 4);
      expect(find.text(errorMessageFor('code_expired')), findsOneWidget);
      expect(auth.verifies, isEmpty);
    });

    testWidgets('an unknown expiry never shows the notice', (tester) async {
      await pumpOtp(tester, args: otpArgs(cooldown: 2, expires: null));
      await clock.advance(tester, 5);
      expect(find.text(errorMessageFor('code_expired')), findsNothing);
    });

    testWidgets('a long pause in the background shows the real time left', (
      tester,
    ) async {
      await pumpOtp(tester);
      clock.elapsed += const Duration(seconds: 100);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('ارسال دوباره تا ۰۰:۲۰'), findsOneWidget);
    });
  });

  group('way back', () {
    testWidgets('the ویرایش chip returns to the phone page', (tester) async {
      await tester.pumpWidget(loginApp(loginRouter(auth, clock: clock)));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '364419970');
      await tester.pump();
      await tester.tap(find.text('فرستادن کد'));
      await flush(tester);
      expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
      await tester.tap(find.text('ویرایش'));
      await flush(tester);
      expect(find.text('با شماره‌ات بیا تو'), findsOneWidget);
    });

    testWidgets('the back button returns to the phone page', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(loginApp(loginRouter(auth, clock: clock)));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '364419970');
      await tester.pump();
      await tester.tap(find.text('فرستادن کد'));
      await flush(tester);
      await tester.tap(find.bySemanticsLabel('بازگشت'));
      await flush(tester);
      expect(find.text('با شماره‌ات بیا تو'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('with nothing under it, back goes to the phone page', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpOtp(tester);
      await tester.tap(find.bySemanticsLabel('بازگشت'));
      await flush(tester);
      expect(find.text('با شماره‌ات بیا تو'), findsOneWidget);
      handle.dispose();
    });
  });

  group('semantics', () {
    testWidgets('the hidden field is reachable and the boxes read as a whole', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpOtp(tester);
      expect(find.bySemanticsLabel('کد چهاررقمی'), findsOneWidget);
      expect(
        find.bySemanticsLabel('کد تأیید، ۰ رقم از ۴ رقم نوشته شده'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '48');
      await tester.pump();
      expect(
        find.bySemanticsLabel('کد تأیید، ۲ رقم از ۴ رقم نوشته شده'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('ویرایش شماره'), findsOneWidget);
      expect(find.bySemanticsLabel(_confirm), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an error is announced as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      auth.verifyAnswers.add(authError('invalid_code'));
      await pumpOtp(tester);
      await typeCode(tester, '1234');
      final node = tester.getSemantics(
        find.bySemanticsLabel(errorMessageFor('invalid_code')),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('contrast', () {
    test('the pairs the OTP page paints, light and dark', () {
      for (final (name, theme) in [
        ('light', AppTheme.light),
        ('dark', AppTheme.dark),
      ]) {
        final z = theme.extension<ZColors>()!;
        final zs = theme.extension<ZScene>()!;
        void atLeast(String pair, Color a, Color b, double min) => expect(
          contrastRatio(a, b),
          greaterThanOrEqualTo(min),
          reason: '$pair ($name)',
        );
        atLeast('digit on tile', z.ink, zs.tile, 4.5);
        atLeast('ink on surface', z.ink, z.surface, 4.5);
        atLeast('ink60 on surface', z.ink60, z.surface, 4.5);
        atLeast('status text on chip', zs.coralInk, z.surface, 4.5);
        atLeast('ویرایش on surface', zs.indigoInk, z.surface, 4.5);
        atLeast('welcome card text', z.onIndigo, z.indigo, 4.5);
        atLeast('confirm button', z.onTeal, z.teal, 3);
        atLeast('disabled button', z.ink60, z.wash, 4.5);
      }
    });
  });

  group('motion on', () {
    testWidgets('runs the entrances, the caret and the mascot', (tester) async {
      await pumpOtp(tester, reduceMotion: false);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('layout grid', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];
    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.3, 1.6, 2.0]) {
          testWidgets(
            'no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '${brightness.name} x$scale',
            (tester) async {
              auth.verifyAnswers.add(authError('too_many_attempts'));
              await pumpOtp(
                tester,
                args: otpArgs(referral: 'K7M2QX'),
                size: size,
                brightness: brightness,
                textScale: scale,
              );
              expect(tester.takeException(), isNull, reason: 'idle');

              tester.view.viewInsets = FakeViewPadding(
                bottom: size.height * .45,
              );
              await flush(tester);
              expect(tester.takeException(), isNull, reason: 'keyboard');

              await tester.enterText(find.byType(TextField), '48');
              await tester.pump();
              expect(tester.takeException(), isNull, reason: 'two digits');

              await clock.advance(tester, 121);
              expect(tester.takeException(), isNull, reason: 'expired');
              expect(
                find.text(errorMessageFor('code_expired')),
                findsOneWidget,
              );

              await typeCode(tester, '4812');
              expect(
                find.text(errorMessageFor('too_many_attempts')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull, reason: 'error');

              tester.view.resetViewInsets();
              await flush(tester);
              await tester.scrollUntilVisible(
                find.text(_confirm),
                100,
                scrollable: find.byType(Scrollable).first,
              );
              expect(tester.takeException(), isNull, reason: 'scrolled');
            },
          );
        }
      }
    }
  });

  group('goldens', () {
    testWidgets('two digits typed, light', (tester) async {
      await pumpOtp(tester);
      await tester.enterText(find.byType(TextField), '48');
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/otp_typing_light.png'),
      );
    });

    testWidgets('resend ready + welcome with referral, light', (tester) async {
      await pumpOtp(
        tester,
        args: otpArgs(cooldown: 2, expires: 200, referral: 'K7M2QX'),
      );
      await clock.advance(tester, 2);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/otp_ready_light.png'),
      );
    });

    testWidgets('wrong code, dark', (tester) async {
      auth.verifyAnswers.add(authError('invalid_code'));
      await pumpOtp(tester, brightness: Brightness.dark);
      await typeCode(tester, '4812');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/otp_error_dark.png'),
      );
    });

    testWidgets('small phone, keyboard open, expired, dark', (tester) async {
      await pumpOtp(
        tester,
        brightness: Brightness.dark,
        size: const Size(320, 568),
        args: otpArgs(cooldown: 2, expires: 2),
      );
      await tester.enterText(find.byType(TextField), '481');
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await clock.advance(tester, 2);
      await flush(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/otp_small_keyboard_dark.png'),
      );
    });
  });
}
