import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/theme/app_game_metrics.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/widgets/insufficient_coins_dialog.dart';
import 'package:wordchain/core/widgets/notification_permission_dialog.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';

import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

class _Auth extends FakeAuthCubit {
  @override
  bool get isGuest => false;
}

class _Ads extends Fake implements AdService {
  @override
  bool get rewardedEnabled => false;
}

class _Notifications extends Fake implements NotificationService {
  final calls = <String>[];

  @override
  Future<bool> isAuthorized() async => false;

  @override
  Future<void> requestPermission() async => calls.add('permission');

  @override
  Future<void> registerToken() async => calls.add('token');
}

/// Opens [open] from a button, the way a screen would.
Widget _host(
  void Function(BuildContext) open, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = true,
}) => zTestApp(
  Builder(
    builder:
        (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
  ),
  brightness: brightness,
  reduceMotion: reduceMotion,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadVazirmatn);

  group('showZDialog', () {
    for (final b in Brightness.values) {
      testWidgets('paints the scrim token behind the card (${b.name})', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            (c) => showZDialog<void>(
              c,
              builder: (_) => const ZDialogCard(child: Text('hello')),
            ),
            brightness: b,
          ),
        );
        await tester.tap(find.text('open'));
        await _settle(tester);

        final scrim =
            (b == Brightness.light ? ZScene.light : ZScene.dark).scrim;
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.color, scrim);
        expect(find.text('hello'), findsOneWidget);
      });
    }

    testWidgets('a tap on the scrim dismisses unless told not to', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (c) => showZDialog<void>(
            c,
            barrierDismissible: false,
            builder: (_) => const ZDialogCard(child: Text('sticky')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tapAt(const Offset(2, 2));
      await _settle(tester);
      expect(find.text('sticky'), findsOneWidget);
    });

    testWidgets('the card keeps the dialog width limits', (tester) async {
      _size(tester, 800, 600);
      await tester.pumpWidget(
        _host(
          (c) => showZDialog<void>(
            c,
            builder: (_) => const ZDialogCard(child: SizedBox(width: 2000)),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(
        tester.getSize(find.byType(ZDialogCard)).width,
        lessThanOrEqualTo(ZGame.dialogMaxWidth),
      );
    });

    testWidgets('a tall dialog scrolls instead of overflowing', (tester) async {
      _size(tester, 320, 320);
      await tester.pumpWidget(
        _host(
          (c) => showZDialog<void>(
            c,
            builder: (_) => const ZDialogCard(child: SizedBox(height: 900)),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the caller\'s text direction', (tester) async {
      TextDirection? seen;
      await tester.pumpWidget(
        _host(
          (c) => showZDialog<void>(
            c,
            builder: (dialogContext) {
              seen = Directionality.of(dialogContext);
              return const ZDialogCard(child: Text('x'));
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(seen, TextDirection.rtl);
    });

    testWidgets('the entrance animates unless motion is reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (c) => showZDialog<void>(
            c,
            builder: (_) => const ZDialogCard(child: Text('hello')),
          ),
          reduceMotion: false,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final early = tester.getTopLeft(find.byType(ZDialogCard)).dy;
      await tester.pump(const Duration(milliseconds: 700));
      final settled = tester.getTopLeft(find.byType(ZDialogCard)).dy;
      // Drops in from above.
      expect(early, lessThan(settled));
    });
  });

  group('ZDialogCard', () {
    testWidgets('a mascot stands on the card and overlaps it', (tester) async {
      await tester.pumpWidget(
        zTestApp(
          const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 300,
                child: ZDialogCard(
                  mascot: ZMascot(size: ZGame.dialogMascotSize, shadow: false),
                  child: SizedBox(height: 40),
                ),
              ),
            ),
          ),
          reduceMotion: true,
        ),
      );
      final mascotTop = tester.getTopLeft(find.byType(ZMascot)).dy;
      final mascotBottom = tester.getBottomLeft(find.byType(ZMascot)).dy;
      final cardTop =
          tester.getTopLeft(find.byType(ZDialogCard)).dy +
          ZGame.dialogMascotLift;
      expect(cardTop, greaterThan(mascotTop));
      expect(cardTop, lessThan(mascotBottom));
    });
  });

  group('ZDialogButton', () {
    testWidgets('primary and secondary call back, and are tall enough', (
      tester,
    ) async {
      var primary = 0, secondary = 0;
      await tester.pumpWidget(
        zTestApp(
          Scaffold(
            body: Column(
              children: [
                ZDialogButton.primary(label: 'yes', onTap: () => primary++),
                ZDialogButton.secondary(label: 'no', onTap: () => secondary++),
              ],
            ),
          ),
          reduceMotion: true,
        ),
      );
      await tester.tap(find.text('yes'));
      await tester.tap(find.text('no'));
      expect((primary, secondary), (1, 1));
      expect(
        tester.getSize(find.text('yes')).height,
        lessThan(ZGame.dialogPrimaryHeight),
      );
      // The whole 58 / 50 box is the hit target.
      expect(
        tester.getSize(find.byType(ZDialogButton).first).height,
        greaterThanOrEqualTo(ZGame.dialogPrimaryHeight),
      );
      expect(
        tester.getSize(find.byType(ZDialogButton).last).height,
        greaterThanOrEqualTo(ZGame.dialogSecondaryHeight),
      );
    });

    testWidgets('a null onTap does nothing', (tester) async {
      await tester.pumpWidget(
        zTestApp(
          const Scaffold(
            body: ZDialogButton.primary(label: 'busy', onTap: null),
          ),
        ),
      );
      await tester.tap(find.text('busy'));
      expect(tester.takeException(), isNull);
    });
  });

  group('insufficient coins', () {
    setUp(() async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<AuthCubit>(_Auth());
      GetIt.I.registerSingleton<AdService>(_Ads());
    });
    tearDown(GetIt.I.reset);

    testWidgets('explains the shortfall and closes', (tester) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_host((c) => showInsufficientCoinsDialog(c)));
      await tester.tap(find.text('open'));
      await _settle(tester);

      expect(find.text('سکهٔ کافی نداری'), findsOneWidget);
      expect(find.textContaining('۲۰ سکه لازم است'), findsOneWidget);
      expect(find.text('چالش روزانه'), findsOneWidget);

      await tester.tap(find.text('متوجه شدم'));
      await _settle(tester);
      expect(find.text('سکهٔ کافی نداری'), findsNothing);
    });

    for (final b in Brightness.values) {
      for (final size in const [Size(320, 568), Size(396, 812)]) {
        testWidgets(
          'no overflow ${size.width.toInt()}×${size.height.toInt()} ${b.name}',
          (tester) async {
            _size(tester, size.width, size.height);
            await tester.pumpWidget(
              _host(
                (c) => showInsufficientCoinsDialog(c, cost: 25),
                brightness: b,
              ),
            );
            await tester.tap(find.text('open'));
            await _settle(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets('golden ${b.name}', (tester) async {
        _size(tester, 396, 812);
        await tester.pumpWidget(
          _host((c) => showInsufficientCoinsDialog(c), brightness: b),
        );
        await tester.tap(find.text('open'));
        await _settle(tester);
        await expectLater(
          find.byType(View).first,
          matchesGoldenFile('goldens/dialog_coins_${b.name}.png'),
        );
      });
    }
  });

  group('notification permission', () {
    late _Notifications notifications;

    setUp(() async {
      await GetIt.I.reset();
      SharedPreferences.setMockInitialValues({});
      GetIt.I.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      notifications = _Notifications();
      GetIt.I.registerSingleton<NotificationService>(notifications);
    });
    tearDown(GetIt.I.reset);

    testWidgets('agreeing asks the OS and registers the token', (tester) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_host((c) => maybeAskNotificationPermission(c)));
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsOneWidget);

      await tester.tap(find.text('فعال‌سازی اعلان‌ها'));
      await _settle(tester);
      expect(notifications.calls, ['permission', 'token']);
    });

    testWidgets('«بعداً» asks nothing, and it is only ever shown once', (
      tester,
    ) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_host((c) => maybeAskNotificationPermission(c)));
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(find.text('بعداً'));
      await _settle(tester);
      expect(notifications.calls, isEmpty);

      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsNothing);
    });

    for (final b in Brightness.values) {
      testWidgets('golden ${b.name}', (tester) async {
        _size(tester, 396, 812);
        await tester.pumpWidget(
          _host((c) => maybeAskNotificationPermission(c), brightness: b),
        );
        await tester.tap(find.text('open'));
        await _settle(tester);
        await expectLater(
          find.byType(View).first,
          matchesGoldenFile('goldens/dialog_notification_${b.name}.png'),
        );
      });
    }
  });
}
