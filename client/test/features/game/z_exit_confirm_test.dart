import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/z_exit_confirm.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

GameActive _active({
  String mode = 'classic',
  String opponent = 'solo',
  int words = 14,
  int score = 320,
}) => GameActive(
  localMatchId: 1,
  mode: mode,
  opponentType: opponent,
  wordChain: List.generate(words, (i) => 'کلمه$i'),
  wordScores: const [],
  score: score,
  streak: 0,
  turnTimeRemaining: 15,
  guestHintUsesLeft: 5,
  continueUsed: false,
);

const _over = GameOver(
  localMatchId: 1,
  mode: 'classic',
  reason: 'timeout',
  score: 10,
  chainLength: 2,
  wordChain: ['سیب', 'بار'],
  canContinue: false,
  continueTimeRemaining: 0,
  isSaved: true,
);

/// A back-button stand-in over [bloc]; tapping it opens the real dialog.
Widget _host(
  ScriptedGameBloc bloc, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) => BlocProvider<GameBloc>.value(
  value: bloc,
  child: zTestApp(
    Builder(
      builder:
          (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => zShowEndGameDialog(context),
                child: const Text('back'),
              ),
            ),
          ),
    ),
    brightness: brightness,
    reduceMotion: reduceMotion,
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('back'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// Lets a route finish closing. `pumpAndSettle` cannot be used: the mascot and
/// the live pill loop forever.
Future<void> _closed(WidgetTester tester) async {
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

  group('mode', () {
    test('is read from the running game', () {
      expect(zExitModeOf(_active()), ZExitMode.solo);
      expect(zExitModeOf(_active(opponent: 'ai_hard')), ZExitMode.ai);
      expect(zExitModeOf(_active(opponent: 'multiplayer')), ZExitMode.online);
      // Daily wins over the (solo) opponent type.
      expect(zExitModeOf(_active(mode: 'daily')), ZExitMode.daily);
    });

    test('only solo and vs-AI stop the clock', () {
      expect(zExitPausesClock(ZExitMode.solo), isTrue);
      expect(zExitPausesClock(ZExitMode.ai), isTrue);
      expect(zExitPausesClock(ZExitMode.online), isFalse);
      // Ranked and prized: leaving the dialog open must not be free time.
      expect(zExitPausesClock(ZExitMode.daily), isFalse);
    });
  });

  group('copy tells the truth about each mode', () {
    ZExitCopy copy(ZExitMode m, {int fee = 0}) =>
        ZExitCopy.of(m, chainLength: 14, score: 320, entryFee: fee);

    test('solo: the game is saved, not thrown away', () {
      final c = copy(ZExitMode.solo);
      expect(c.title, 'زنجیرت نصفه می‌مونه!');
      expect(c.body, isNot(contains('ذخیره نمی‌شه')));
      expect(c.body, contains('ثبت می‌شه'));
      expect(c.stakes, [('۱۴ کلمه', 'زنجیر فعلی'), ('۳۲۰', 'امتیاز')]);
      expect(c.live, isFalse);
      expect(c.leave, 'خروج');
    });

    test('vs-AI: no loss is recorded', () {
      final c = copy(ZExitMode.ai);
      expect(c.title, 'بازی رو وا می‌دی؟');
      expect(c.body, isNot(contains('باخت')));
      expect(c.stakes.map((s) => s.$1), isNot(contains('باخت')));
      expect(c.leave, 'تسلیم و خروج');
      expect(c.live, isFalse);
    });

    test('online: the entry fee is only mentioned when there is one', () {
      final paid = copy(ZExitMode.online, fee: 20);
      expect(paid.body, contains('۲۰ سکه'));
      expect(paid.stakes.first, ('−۲۰ سکه', 'ورودی بازی'));
      expect(paid.stakes.last, ('باخت', 'نتیجهٔ بازی'));
      expect(paid.live, isTrue);
      expect(paid.pill, 'تایمر متوقف نمی‌شه');
      expect(paid.stay, 'برمی‌گردم');

      final free = copy(ZExitMode.online);
      expect(free.body, isNot(contains('سکه')));
      expect(free.stakes, [('باخت', 'نتیجهٔ بازی')]);
    });

    test('no mode invents a rank, a streak or a prize', () {
      for (final m in ZExitMode.values) {
        final text =
            '${copy(m, fee: 20).body} ${copy(m, fee: 20).stakes.join(' ')}';
        expect(text, isNot(contains('رتبه')), reason: '$m');
        expect(text, isNot(contains('رکورد پیاپی')), reason: '$m');
        expect(text, isNot(contains('جایزه')), reason: '$m');
        expect(text, isNot(contains('تا فردا')), reason: '$m');
      }
    });

    test('daily: the attempt is posted with its score', () {
      final c = copy(ZExitMode.daily);
      expect(c.body, contains('توی جدول امروز ثبت می‌شه'));
      expect(c.stakes, [('۱۴ کلمه', 'زنجیر فعلی'), ('۳۲۰', 'امتیاز')]);
      expect(c.live, isTrue);
    });
  });

  group('behaviour', () {
    testWidgets('solo pauses, and staying resumes', (tester) async {
      final bloc = ScriptedGameBloc(_active());
      await tester.pumpWidget(_host(bloc));
      await _open(tester);

      expect(bloc.events.single, isA<GamePaused>());
      expect(find.text('زنجیرت نصفه می‌مونه!'), findsOneWidget);

      await tester.tap(find.text('ادامه می‌دم'));
      await _closed(tester);

      expect(bloc.events.map((e) => e.runtimeType), [GamePaused, GameResumed]);
      expect(find.text('زنجیرت نصفه می‌مونه!'), findsNothing);
    });

    testWidgets('leaving ends the game (and does not resume)', (tester) async {
      final bloc = ScriptedGameBloc(_active(opponent: 'ai_medium'));
      await tester.pumpWidget(_host(bloc));
      await _open(tester);
      expect(find.text('بازی رو وا می‌دی؟'), findsOneWidget);

      await tester.tap(find.text('تسلیم و خروج'));
      await _closed(tester);

      expect(bloc.events.map((e) => e.runtimeType), [GamePaused, GameEnded]);
    });

    testWidgets('tapping the scrim is "stay"', (tester) async {
      final bloc = ScriptedGameBloc(_active());
      await tester.pumpWidget(_host(bloc));
      await _open(tester);

      await tester.tapAt(const Offset(4, 4));
      await _closed(tester);

      expect(bloc.events.map((e) => e.runtimeType), [GamePaused, GameResumed]);
      expect(find.text('ادامه می‌دم'), findsNothing);
    });

    testWidgets('online never pauses; leaving still just ends it', (
      tester,
    ) async {
      final bloc = ScriptedGameBloc(
        _active(opponent: 'multiplayer'),
        entryFee: 20,
      );
      await tester.pumpWidget(_host(bloc));
      await _open(tester);

      expect(bloc.events, isEmpty);
      expect(find.text('تسلیم می‌شی؟'), findsOneWidget);
      expect(find.textContaining('۲۰ سکهٔ ورودی'), findsOneWidget);

      await tester.tap(find.text('تسلیم و خروج'));
      await _closed(tester);
      expect(bloc.events.single, isA<GameEnded>());
    });

    testWidgets('daily does not pause either', (tester) async {
      final bloc = ScriptedGameBloc(_active(mode: 'daily'));
      await tester.pumpWidget(_host(bloc));
      await _open(tester);

      expect(bloc.events, isEmpty);
      expect(find.text('تلاش امروزت تموم می‌شه!'), findsOneWidget);
      await tester.tap(find.text('ادامه می‌دم'));
      await _closed(tester);
      expect(bloc.events, isEmpty);
    });

    testWidgets('closes itself when the game ends underneath', (tester) async {
      final bloc = ScriptedGameBloc(_active(opponent: 'multiplayer'));
      await tester.pumpWidget(_host(bloc));
      await _open(tester);
      expect(find.text('تسلیم می‌شی؟'), findsOneWidget);

      bloc.push(_over);
      await _closed(tester);

      expect(find.text('تسلیم می‌شی؟'), findsNothing);
      // The game is already over: nothing to end, nothing to resume.
      expect(bloc.events, isEmpty);
    });

    testWidgets('does nothing when no game is running', (tester) async {
      final bloc = ScriptedGameBloc(const GameInitial());
      await tester.pumpWidget(_host(bloc));
      await tester.tap(find.text('back'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(ZExitConfirm), findsNothing);
      expect(bloc.events, isEmpty);
    });

    testWidgets('reduced motion fades instead of dropping in', (tester) async {
      final bloc = ScriptedGameBloc(_active());
      await tester.pumpWidget(_host(bloc, reduceMotion: true));
      await tester.tap(find.text('back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('زنجیرت نصفه می‌مونه!'), findsOneWidget);
      // Settled: no animation left scheduled by the dialog or its mascot.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('layout', () {
    for (final brightness in Brightness.values) {
      for (final mode in ZExitMode.values) {
        for (final size in const [
          Size(320, 568),
          Size(360, 640),
          Size(393, 852),
          Size(430, 932),
        ]) {
          testWidgets(
            'no overflow ${mode.name} ${size.width.toInt()}×${size.height.toInt()} ${brightness.name}',
            (tester) async {
              _size(tester, size.width, size.height);
              final bloc = ScriptedGameBloc(switch (mode) {
                ZExitMode.solo => _active(),
                ZExitMode.ai => _active(opponent: 'ai_hard'),
                ZExitMode.online => _active(opponent: 'multiplayer'),
                ZExitMode.daily => _active(mode: 'daily', words: 120),
              }, entryFee: 20);
              await tester.pumpWidget(
                _host(bloc, brightness: brightness, reduceMotion: true),
              );
              await _open(tester);
              expect(tester.takeException(), isNull);
              expect(find.byType(ZExitConfirm), findsOneWidget);
              // Both buttons reachable and tall enough to tap.
              for (final label in [
                if (mode == ZExitMode.online) 'برمی‌گردم' else 'ادامه می‌دم',
                if (mode == ZExitMode.solo || mode == ZExitMode.daily)
                  'خروج'
                else
                  'تسلیم و خروج',
              ]) {
                expect(
                  tester.getSize(find.text(label)).height,
                  greaterThan(0),
                  reason: label,
                );
              }
            },
          );
        }
      }
    }

    testWidgets('large text scale still fits', (tester) async {
      _size(tester, 360, 640);
      final bloc = ScriptedGameBloc(
        _active(opponent: 'multiplayer'),
        entryFee: 20,
      );
      await tester.pumpWidget(
        BlocProvider<GameBloc>.value(
          value: bloc,
          child: zTestApp(
            Builder(
              builder:
                  (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: const TextScaler.linear(1.6),
                      disableAnimations: true,
                    ),
                    child: Scaffold(
                      body: TextButton(
                        onPressed: () => zShowEndGameDialog(context),
                        child: const Text('back'),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );
      await _open(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('contrast', () {
    for (final b in Brightness.values) {
      test('pairings ≥ 4.5:1 (${b.name})', () {
        final z = b == Brightness.light ? ZColors.light : ZColors.dark;
        final zs = b == Brightness.light ? ZScene.light : ZScene.dark;
        // Leave label and icon on the secondary button.
        expect(
          contrastRatio(zs.coralInk, z.surface),
          greaterThanOrEqualTo(4.5),
        );
        // Body copy, header and stake labels sit on surface / wash.
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        // Status pills.
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrastRatio(zs.onCoralSm, z.coral), greaterThanOrEqualTo(4.5));
        // Primary button label: 19sp / 900 is large text (3:1).
        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
      });
    }
  });

  group('goldens', () {
    Future<void> shoot(
      WidgetTester tester,
      ScriptedGameBloc bloc,
      Brightness b,
      String name,
    ) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_host(bloc, brightness: b, reduceMotion: true));
      await _open(tester);
      await expectLater(
        find.byType(View).first,
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    testWidgets('solo light', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active()),
        Brightness.light,
        'z_exit_solo_light',
      );
    });
    testWidgets('solo dark', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active()),
        Brightness.dark,
        'z_exit_solo_dark',
      );
    });
    testWidgets('ai light', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active(opponent: 'ai_medium', score: 320)),
        Brightness.light,
        'z_exit_ai_light',
      );
    });
    testWidgets('online light', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active(opponent: 'multiplayer'), entryFee: 20),
        Brightness.light,
        'z_exit_online_light',
      );
    });
    testWidgets('online dark', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active(opponent: 'multiplayer'), entryFee: 20),
        Brightness.dark,
        'z_exit_online_dark',
      );
    });
    testWidgets('daily light', (t) async {
      await shoot(
        t,
        ScriptedGameBloc(_active(mode: 'daily', words: 9, score: 460)),
        Brightness.light,
        'z_exit_daily_light',
      );
    });
  });
}
