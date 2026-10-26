import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/widgets/z_opp_deciding.dart';

import '../../helpers/z_test_app.dart';

Future<void> _show(
  WidgetTester tester, {
  required int remaining,
  String? lossReason,
  VoidCallback? onUnderTap,
}) async {
  tester.view.physicalSize = const Size(396, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    zTestApp(
      Material(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUnderTap,
              ),
            ),
            ZOppDecidingOverlay(remaining: remaining, lossReason: lossReason),
          ],
        ),
      ),
      reduceMotion: true,
    ),
  );
  // The mascot loops forever, so settle by time, not pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Color _numberColor(WidgetTester tester, String digits) =>
    tester.widget<Text>(find.text(digits)).style!.color!;

void main() {
  setUpAll(loadVazirmatn);

  testWidgets('shows the seconds left in Persian digits', (tester) async {
    await _show(tester, remaining: 11);
    expect(find.text('۱۱'), findsOneWidget);
    expect(find.text('ثانیه'), findsOneWidget);
    expect(find.text('حریف داره تصمیم می‌گیره…'), findsOneWidget);
  });

  testWidgets('the number follows the countdown it is given', (tester) async {
    await _show(tester, remaining: 9);
    expect(find.text('۹'), findsOneWidget);
    await tester.pumpWidget(
      zTestApp(
        Material(
          child: Stack(children: const [ZOppDecidingOverlay(remaining: 8)]),
        ),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(find.text('۸'), findsOneWidget);
    expect(find.text('۹'), findsNothing);
  });

  testWidgets('the number turns coral for the last three seconds', (
    tester,
  ) async {
    await _show(tester, remaining: 4);
    final zs = tester.element(find.byType(ZOppDecidingCard)).zs;
    expect(_numberColor(tester, '۴'), isNot(zs.coralInk));

    await _show(tester, remaining: 3);
    expect(_numberColor(tester, '۳'), zs.coralInk);
  });

  testWidgets('states the real continue price, not the canvas 20', (
    tester,
  ) async {
    await _show(tester, remaining: 10);
    expect(find.text('۲۵ سکه'), findsOneWidget);
    expect(GameConstants.continueCostCoins, 25);
    expect(find.text('اگه تا آخر زمان ادامه نده، تو می‌بری'), findsOneWidget);
  });

  testWidgets('the body names why the opponent lost', (tester) async {
    await _show(tester, remaining: 10, lossReason: 'invalid_word');
    expect(find.textContaining('کلمهٔ حریف رد شد'), findsOneWidget);

    await _show(tester, remaining: 10, lossReason: 'timeout');
    expect(find.textContaining('وقت حریف تموم شد'), findsOneWidget);
    expect(find.textContaining('کلمهٔ حریف رد شد'), findsNothing);
  });

  testWidgets('the scrim blocks taps on the game underneath', (tester) async {
    var taps = 0;
    await _show(tester, remaining: 10, onUnderTap: () => taps++);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(taps, 0);
  });
}
