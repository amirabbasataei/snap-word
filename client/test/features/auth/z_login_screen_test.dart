import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/auth/data/auth_repository.dart';
import 'package:wordchain/features/auth/view/widgets/referral_bottom_sheet.dart';

import '../../helpers/contrast.dart';
import '../../helpers/z_test_app.dart';
import 'auth_fakes.dart';

late FakeAuth auth;
late TestClock clock;
late List<String> visited;

const _title = 'با شماره‌ات بیا تو';
const _send = 'فرستادن کد';
const _phone = '09364419970';

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpLogin(
  WidgetTester tester, {
  String initial = '/login',
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
      loginRouter(auth, initial: initial, clock: clock, visited: visited),
      brightness: brightness,
      textScale: textScale,
      reduceMotion: reduceMotion,
    ),
  );
  await flush(tester);
}

Future<void> typePhone(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

Future<void> tapSend(WidgetTester tester) async {
  await tester.tap(find.text(_send));
  await flush(tester);
}

/// Types the number and sends; leaves the OTP page showing.
Future<void> sendCode(WidgetTester tester) async {
  await typePhone(tester, _phone);
  await tapSend(tester);
}

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField).last, code);
  await flush(tester);
}

/// Lets a toast (2.6 s) and its fade finish.
Future<void> waitOutToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 1));
}

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

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

  group('idle', () {
    testWidgets(
      'shows the canvas content and nothing the server does not back',
      (tester) async {
        await pumpLogin(tester);
        expect(find.text(_title), findsOneWidget);
        expect(
          find.text('یک کد چهاررقمی برایت می‌فرستیم. رمزی در کار نیست.'),
          findsOneWidget,
        );
        expect(find.text('شمارهٔ موبایل'), findsOneWidget);
        expect(find.text('۰۹'), findsOneWidget);
        expect(find.textContaining('قوانین و حریم خصوصی'), findsOneWidget);
        expect(find.text(_send), findsOneWidget);
        expect(find.text('کد دعوت داری؟'), findsOneWidget);
        expect(
          find.text('با شمارهٔ تازه ۱۰۰ سکه، بعد از ورود ۵۰ سکه'),
          findsOneWidget,
        );
        expect(find.text('فعلاً مهمان می‌مانم'), findsOneWidget);
        expect(find.text('امتیاز مهمان روی این گوشی می‌ماند'), findsOneWidget);
        expect(find.text('حرف آخر، حرف اول!'), findsOneWidget);
        // No carrier, no player counts, no checkbox gate.
        for (final invented in [
          'ایرانسل',
          'همراه اول',
          'رایتل',
          'اپراتور',
          'نفر',
        ]) {
          expect(find.textContaining(invented), findsNothing, reason: invented);
        }
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('شمارهٔ ایران'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the send button does nothing before the number is complete', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tapSend(tester);
      expect(auth.sentTo, isEmpty);
      await typePhone(tester, '9364');
      await tapSend(tester);
      expect(auth.sentTo, isEmpty);
      expect(find.text('شمارهٔ ایران'), findsNothing);
    });

    testWidgets('a complete number shows the Iran chip and enables sending', (
      tester,
    ) async {
      await pumpLogin(tester);
      await typePhone(tester, '364419970');
      expect(find.text('شمارهٔ ایران'), findsOneWidget);
      expect(fieldText(tester), '۳۶ ۴۴۱ ۹۹۷۰');
      await typePhone(tester, '36441997');
      expect(find.text('شمارهٔ ایران'), findsNothing);
    });
  });

  group('sending the code', () {
    testWidgets('success opens the OTP page with the number and cooldown', (
      tester,
    ) async {
      auth.sendAnswers.add(
        const SendOtpResult(expiresInSeconds: 120, resendCooldownSeconds: 110),
      );
      await pumpLogin(tester);
      await sendCode(tester);
      expect(auth.sentTo, [_phone]);
      expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
      expect(find.text('۰۹۳۶۴۴۱۹۹۷۰'), findsOneWidget);
      expect(find.text('ارسال دوباره تا ۰۱:۵۰'), findsOneWidget);
    });

    testWidgets('Persian and Arabic digits are normalised before sending', (
      tester,
    ) async {
      await pumpLogin(tester);
      await typePhone(tester, '۳۶۴۴۱۹۹۷۰');
      await tapSend(tester);
      expect(auth.sentTo, [_phone]);
    });

    testWidgets('the keyboard\'s done key sends too', (tester) async {
      await pumpLogin(tester);
      await typePhone(tester, '364419970');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      expect(auth.sentTo, [_phone]);
    });

    testWidgets('done with an incomplete number sends nothing', (tester) async {
      await pumpLogin(tester);
      await typePhone(tester, '3644');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      expect(auth.sentTo, isEmpty);
    });

    testWidgets(
      'while the request is out the button waits and the field locks',
      (tester) async {
        auth.sendGate = Completer();
        await pumpLogin(tester);
        await typePhone(tester, '364419970');
        await tapSend(tester);
        expect(find.text('در حال فرستادن کد…'), findsOneWidget);
        expect(find.text(_send), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        await tester.tap(find.text('در حال فرستادن کد…'));
        await flush(tester);
        expect(auth.sentTo.length, 1);

        auth.sendGate!.complete(defaultSend);
        await flush(tester);
        expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
      },
    );

    for (final code in [
      'invalid_phone',
      'rate_limited',
      'resend_cooldown',
      'validation_error',
    ]) {
      testWidgets('server error $code shows its Persian message', (
        tester,
      ) async {
        auth.sendAnswers.add(authError(code));
        await pumpLogin(tester);
        await sendCode(tester);
        expect(find.text(errorMessageFor(code)), findsOneWidget);
        expect(find.textContaining('server says'), findsNothing);
        // Back on the phone page, ready to try again.
        expect(find.text(_title), findsOneWidget);
        expect(find.text(_send), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
      });
    }

    testWidgets('a network failure says so', (tester) async {
      auth.sendAnswers.add(const NetworkException(networkErrorMessage));
      await pumpLogin(tester);
      await sendCode(tester);
      expect(find.text(networkErrorMessage), findsOneWidget);
    });

    testWidgets('typing again clears the message, retrying works', (
      tester,
    ) async {
      auth.sendAnswers
        ..add(authError('rate_limited'))
        ..add(defaultSend);
      await pumpLogin(tester);
      await sendCode(tester);
      expect(find.text(errorMessageFor('rate_limited')), findsOneWidget);
      await typePhone(tester, '36441997');
      expect(find.text(errorMessageFor('rate_limited')), findsNothing);
      await typePhone(tester, '364419970');
      await tapSend(tester);
      expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
    });

    testWidgets('back from the OTP page keeps the number', (tester) async {
      await pumpLogin(tester);
      await sendCode(tester);
      await tester.tap(find.text('ویرایش'));
      await flush(tester);
      expect(find.text(_title), findsOneWidget);
      expect(fieldText(tester), '۳۶ ۴۴۱ ۹۹۷۰');
      expect(find.text('شمارهٔ ایران'), findsOneWidget);
    });

    testWidgets(
      'the same number again inside the cooldown reopens the OTP page '
      'with the time left',
      (tester) async {
        await pumpLogin(tester);
        await sendCode(tester);
        await tester.tap(find.text('ویرایش'));
        await flush(tester);
        clock.elapsed += const Duration(seconds: 50);
        auth.sendAnswers.add(authError('resend_cooldown'));
        await tapSend(tester);
        expect(find.text('کد چهاررقمی را بزن'), findsOneWidget);
        expect(find.text('ارسال دوباره تا ۰۱:۱۰'), findsOneWidget);
        expect(find.text(errorMessageFor('resend_cooldown')), findsNothing);
      },
    );
  });

  group('referral code', () {
    Finder sheetField() => find.descendant(
      of: find.byType(ReferralBottomSheet),
      matching: find.byType(TextField),
    );

    testWidgets('the teaser opens the existing sheet; the code is stashed', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.tap(find.text('کد دعوت داری؟'));
      await flush(tester);
      expect(find.byType(ReferralBottomSheet), findsOneWidget);
      await tester.enterText(sheetField(), 'k7m2qx');
      await tester.tap(find.text('ثبت کد'));
      await flush(tester);
      expect(find.byType(ReferralBottomSheet), findsNothing);
      expect(find.text('کد دعوت ثبت شد'), findsOneWidget);
      expect(find.text('برای عوض کردنش بزن'), findsOneWidget);
      expect(auth.sentTo, isEmpty);
    });

    testWidgets('it reaches verify-otp with the code', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('کد دعوت داری؟'));
      await flush(tester);
      await tester.enterText(sheetField(), 'k7m2qx');
      await tester.tap(find.text('ثبت کد'));
      await flush(tester);
      await sendCode(tester);
      auth.verifyAnswers.add(newcomer(coins: 150));
      await typeCode(tester, '1111');
      expect(auth.verifies.single.referral, 'K7M2QX');
      await waitOutToast(tester);
    });

    testWidgets('closing the sheet without a code changes nothing', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.tap(find.text('کد دعوت داری؟'));
      await flush(tester);
      await tester.tapAt(const Offset(10, 10));
      await flush(tester);
      expect(find.text('کد دعوت داری؟'), findsOneWidget);
      expect(find.text('کد دعوت ثبت شد'), findsNothing);
    });
  });

  group('guest', () {
    testWidgets('«فعلاً مهمان می‌مانم» goes straight to Home', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('فعلاً مهمان می‌مانم'));
      await flush(tester);
      expect(auth.guestTaps, 1);
      expect(find.text('page:home'), findsOneWidget);
      expect(auth.sentTo, isEmpty);
    });
  });

  group('return= redirect', () {
    for (final target in ['/friends', '/leaderboard', '/daily']) {
      testWidgets('a guest sent from $target lands back on it after login', (
        tester,
      ) async {
        await pumpLogin(tester, initial: '/login?return=$target');
        await sendCode(tester);
        await typeCode(tester, '1111');
        expect(
          find.text(
            'page:${target.substring(1)}'.replaceAll('leaderboard', 'board'),
          ),
          findsOneWidget,
        );
        expect(visited, isNot(contains('/home')), reason: 'no flash of Home');
        await waitOutToast(tester);
      });
    }

    testWidgets(
      'the daily redirect for a guest ends back on the daily screen',
      (tester) async {
        await pumpLogin(tester, initial: '/daily');
        expect(find.text(_title), findsOneWidget);
        await sendCode(tester);
        await typeCode(tester, '1111');
        expect(find.text('page:daily'), findsOneWidget);
        await waitOutToast(tester);
      },
    );

    testWidgets('without a target a login ends on Home', (tester) async {
      await pumpLogin(tester);
      await sendCode(tester);
      await typeCode(tester, '1111');
      expect(find.text('page:home'), findsOneWidget);
    });

    testWidgets('a signed-in player who opens /login is sent on at once', (
      tester,
    ) async {
      auth.emitState(
        const AuthAuthenticated(userId: 'u', username: 'n', coins: 1),
      );
      await pumpLogin(tester, initial: '/login?return=/friends');
      expect(find.text('page:friends'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('names the field and each action once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLogin(tester);
      expect(find.bySemanticsLabel('شمارهٔ موبایل'), findsOneWidget);
      expect(find.bySemanticsLabel(_send), findsOneWidget);
      expect(find.bySemanticsLabel('فعلاً مهمان می‌مانم'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^کد دعوت داری؟')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an error is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      auth.sendAnswers.add(authError('rate_limited'));
      await pumpLogin(tester);
      await sendCode(tester);
      final node = tester.getSemantics(
        find.bySemanticsLabel(errorMessageFor('rate_limited')),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });

  group('contrast', () {
    test('the pairs the phone page paints, light and dark', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final z = theme.extension<ZColors>()!;
        final zs = theme.extension<ZScene>()!;
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(zs.indigoInk, z.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(zs.coralInk, z.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrastRatio(zs.tealInk, zs.tile), greaterThanOrEqualTo(4.3));
        expect(contrastRatio(z.ink, zs.tile), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('motion on', () {
    testWidgets('runs the entrances and loops without errors', (tester) async {
      await pumpLogin(tester, reduceMotion: false);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(_title), findsOneWidget);
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
              auth.sendAnswers.add(authError('rate_limited'));
              await pumpLogin(
                tester,
                size: size,
                brightness: brightness,
                textScale: scale,
              );
              expect(tester.takeException(), isNull, reason: 'idle');

              await typePhone(tester, '364419970');
              expect(tester.takeException(), isNull, reason: 'valid');

              // Keyboard open.
              tester.view.viewInsets = FakeViewPadding(
                bottom: size.height * .45,
              );
              await flush(tester);
              expect(tester.takeException(), isNull, reason: 'keyboard');
              tester.view.resetViewInsets();
              await flush(tester);

              await tapSend(tester);
              expect(
                find.text(errorMessageFor('rate_limited')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull, reason: 'error');

              // The send button stays reachable by scrolling.
              await tester.scrollUntilVisible(
                find.text('فعلاً مهمان می‌مانم'),
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
    testWidgets('idle light', (tester) async {
      await pumpLogin(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login_idle_light.png'),
      );
    });

    testWidgets('idle dark', (tester) async {
      await pumpLogin(tester, brightness: Brightness.dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login_idle_dark.png'),
      );
    });

    testWidgets('number typed, rate limited, light', (tester) async {
      auth.sendAnswers.add(authError('rate_limited'));
      await pumpLogin(tester);
      await sendCode(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login_error_light.png'),
      );
    });

    testWidgets('small phone, keyboard open, dark', (tester) async {
      await pumpLogin(
        tester,
        brightness: Brightness.dark,
        size: const Size(320, 568),
      );
      await typePhone(tester, '364419970');
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await flush(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/login_small_keyboard_dark.png'),
      );
    });
  });
}
