import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/iran_time.dart';
import 'package:wordchain/features/home/view/widgets/home_buttons.dart';
import 'package:wordchain/features/home/view/widgets/home_chest.dart';
import 'package:wordchain/features/home/view/widgets/home_daily_ribbon.dart';
import 'package:wordchain/features/home/view/widgets/home_progress_path.dart';
import 'package:wordchain/features/home/view/widgets/home_view.dart';

import '../../helpers/z_test_app.dart';

Widget _home({
  HomeViewData data = const HomeViewData(),
  VoidCallback? onPlay,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
}) {
  void noop() {}
  return zTestApp(
    Builder(
      builder:
          (context) => MediaQuery(
            // The shell's floating dock reaches HomeView as bottom padding
            // (`extendBody`), ~100dp on top of the home-indicator inset.
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              padding: const EdgeInsets.only(bottom: 100),
            ),
            child: HomeView(
              data: data,
              onPlay: onPlay ?? noop,
              onAi: noop,
              onOnline: noop,
              onDaily: noop,
              onChest: noop,
              onCoins: noop,
              onSettings: noop,
              onLevel: noop,
              onResume: noop,
            ),
          ),
    ),
    brightness: brightness,
  );
}

Future<void> _setSize(WidgetTester tester, double w, double h) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadVazirmatn);

  group('hero chain content', () {
    test('is a valid word chain (last letter → next first letter)', () {
      const words = HomeView.heroWords;
      for (var i = 0; i < words.length - 1; i++) {
        expect(
          words[i].runes.last,
          words[i + 1].runes.first,
          reason: '${words[i]} → ${words[i + 1]}',
        );
      }
    });

    test('every word is in the Persian dictionary', () {
      final dict = File('assets/words/fa.txt').readAsLinesSync().toSet();
      for (final w in HomeView.heroWords) {
        expect(dict, contains(w));
      }
    });
  });

  group('formatting', () {
    test('XP label is current / target, in Persian digits', () {
      expect(HomeProgressPath.xpLabel(320, 500), '۳۲۰ / ۵۰۰');
      expect(HomeProgressPath.xpLabel(0, 1000), '۰ / ۱٬۰۰۰');
    });

    test('countdown counts down to the next Iran midnight', () {
      // 21:30 UTC = 01:00 Iran (+03:30) → 23h left.
      final now = DateTime.utc(2026, 10, 15, 21, 30);
      expect(HomeDailyRibbon.countdown(now), '۲۳:۰۰:۰۰');
      expect(untilIranMidnight(now), const Duration(hours: 23));
      // 20:29:15 UTC = 23:59:15 Iran → 45 s left.
      expect(
        HomeDailyRibbon.countdown(DateTime.utc(2026, 10, 15, 20, 29, 15)),
        '۰۰:۰۰:۴۵',
      );
    });

    test('date label is the Jalali day in Iran time', () {
      // 2026-10-16 → ۲۴ مهر ۱۴۰۵.
      expect(
        HomeDailyRibbon.dateLabel(DateTime.utc(2026, 10, 16, 9)),
        '۲۴ مهر',
      );
      // 21:00 UTC is already the next day in Iran (00:30).
      expect(
        HomeDailyRibbon.dateLabel(DateTime.utc(2026, 10, 15, 21)),
        '۲۴ مهر',
      );
    });

    test('online count line', () {
      expect(HomeOnlineButton.onlineCountLabel(3401), '۳٬۴۰۱ نفر آنلاین');
    });
  });

  group('layout', () {
    for (final size in const [
      Size(320, 568), // small phone
      Size(360, 640),
      Size(393, 852),
      Size(430, 932), // tall phone
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets('no overflow ${size.width}x${size.height} $brightness', (
          tester,
        ) async {
          await _setSize(tester, size.width, size.height);
          await tester.pumpWidget(
            _home(
              brightness: brightness,
              data: const HomeViewData(
                coins: 1240,
                streak: 7,
                level: 12,
                xpInLevel: 320,
                xpForNext: 500,
                unclaimedRewards: 2,
                hasActiveMatch: true,
                onlineCount: 3401,
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
          expect(find.text('بازی'), findsOneWidget);
          expect(find.text('رویارویی آنلاین'), findsOneWidget);
        });
      }
    }
  });

  group('interaction', () {
    testWidgets('Play fires onPlay and sinks while pressed', (tester) async {
      await _setSize(tester, 393, 852);
      var played = 0;
      await tester.pumpWidget(_home(onPlay: () => played++));
      await tester.pump(const Duration(milliseconds: 100));

      final play = find.text('بازی');
      expect(play, findsOneWidget);
      final restY = tester.getTopLeft(play).dy;

      final gesture = await tester.startGesture(tester.getCenter(play));
      // onTapDown fires after kPressTimeout; the sink animation takes 90ms.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getTopLeft(play).dy,
        greaterThan(restY + 4),
        reason: 'pressed face sinks by depth − 2',
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(played, 1);
      expect(tester.getTopLeft(play).dy, closeTo(restY, 1.5));
    });

    testWidgets('chest tag only when rewards are waiting', (tester) async {
      await _setSize(tester, 393, 852);
      await tester.pumpWidget(_home());
      expect(find.text(HomeChest.readyLabel), findsNothing);
      await tester.pumpWidget(
        _home(data: const HomeViewData(unclaimedRewards: 1)),
      );
      expect(find.text(HomeChest.readyLabel), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('no idle loop keeps scheduling frames', (tester) async {
      await _setSize(tester, 393, 852);
      await tester.pumpWidget(
        _home(
          reduceMotion: true,
          data: const HomeViewData(unclaimedRewards: 1),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('idle loops run otherwise', (tester) async {
      await _setSize(tester, 393, 852);
      await tester.pumpWidget(_home());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
    });
  });
}
