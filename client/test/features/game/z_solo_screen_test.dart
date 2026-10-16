import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/z_solo_screen.dart';

import '../../helpers/z_test_app.dart';

class _FakeAuth extends Fake implements AuthCubit {
  @override
  AuthState get state => const AuthGuest();

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

/// Records the events the screen adds; the screen reads state from its
/// constructor, so nothing else is needed.
class _FakeGame extends Fake implements GameBloc {
  final events = <GameEvent>[];

  @override
  void add(GameEvent event) => events.add(event);

  @override
  GameState get state => const GameInitial();

  @override
  Stream<GameState> get stream => const Stream.empty();

  @override
  Future<void> close() async {}
}

GameActive _state({
  String mode = 'classic',
  List<String> words = const [],
  List<int> scores = const [],
  String? next,
  int lives = 2,
  int time = 15,
  int score = 0,
  String? mistake,
  Map<String, int> counts = const {},
}) => GameActive(
  localMatchId: 1,
  mode: mode,
  opponentType: 'solo',
  wordChain: words,
  wordScores: scores,
  score: score,
  streak: 0,
  turnTimeRemaining: time,
  nextStartLetter: next,
  guestHintUsesLeft: 5,
  continueUsed: false,
  livesRemaining: lives,
  lastMistakeReason: mistake,
  powerupCounts: counts,
);

const _chain = [
  'سیب',
  'باران',
  'نمک',
  'کتاب',
  'برف',
  'فرش',
  'شیر',
  'رنگ',
  'گاو',
  'واژه',
];
const _scores = [30, 50, 30, 40, 30, 40, 30, 40, 30, 40];

Widget _screen(
  GameActive s, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) => BlocProvider<GameBloc>.value(
  value: _FakeGame(),
  child: zTestApp(
    Builder(
      builder:
          (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: ZSoloActiveScreen(state: s),
          ),
    ),
    brightness: brightness,
  ),
);

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

double _lum(Color c) {
  double ch(double v) =>
      v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final l1 = _lum(a);
  final l2 = _lum(b);
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}

void main() {
  setUpAll(loadVazirmatn);

  setUp(() {
    GetIt.I.registerSingleton<AuthCubit>(_FakeAuth());
  });
  tearDown(() => GetIt.I.reset());

  group('states', () {
    testWidgets('empty chain: first-word prompt, no previous-words chip', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('تک‌نفره'), findsOneWidget);
      expect(find.text('اولین کلمه رو بنویس'), findsOneWidget);
      expect(find.textContaining('کلمهٔ قبلی'), findsNothing);
      expect(find.text('۱۵ ثانیه'), findsOneWidget);
    });

    testWidgets('mid-game: words, points, next-letter slot, score, timer', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(
          _state(
            words: _chain.take(3).toList(),
            scores: _scores.take(3).toList(),
            next: 'ک',
            score: 110,
            time: 4,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('سیب'), findsOneWidget);
      expect(find.bySemanticsLabel('نمک'), findsOneWidget);
      expect(find.text('+۳۰'), findsWidgets);
      expect(find.text('۱۱۰'), findsOneWidget);
      expect(find.text('۰۴'), findsOneWidget);
      expect(find.text('حالا با «ک»'), findsOneWidget);
      expect(find.text('۳ کلمه'), findsOneWidget);
      expect(find.bySemanticsLabel('۴ ثانیه'), findsOneWidget);
    });

    testWidgets('long chain shows the earlier-words chip', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: _chain, scores: _scores, next: 'ه')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('۴ کلمهٔ قبلی'), findsOneWidget);
    });

    testWidgets('daily mode: daily title and word cap, no timed toggle', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(mode: 'daily')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('چالش روزانه'), findsOneWidget);
      expect(find.text('حداکثر ۲۰ کلمه'), findsOneWidget);
      expect(find.text('زمان‌دار'), findsNothing);
      expect(find.text('کلاسیک'), findsNothing);
    });

    testWidgets('lives: spent lives are announced and drawn empty', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(lives: 1)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('۱ جان'), findsOneWidget);
      expect(find.byType(ZLivesChip), findsOneWidget);
    });

    testWidgets('mistake banner', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(mistake: 'invalid_word')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('کلمهٔ اشتباه — یک جان از دست دادی!'), findsOneWidget);
    });

    testWidgets('power-ups: count badge, else coin price badge', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      // Guest: 5 free hints; the others fall back to no badge (guest).
      expect(find.text('۵'), findsOneWidget);
      expect(find.text('راهنما'), findsOneWidget);
      expect(find.text('وقت بیشتر'), findsOneWidget);
      expect(find.text('سپر'), findsOneWidget);
    });

    testWidgets('typing and sending a word dispatches WordSubmitted', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FakeGame();
      final s = _state(next: 'س');
      await tester.pumpWidget(
        BlocProvider<GameBloc>.value(
          value: bloc,
          child: zTestApp(ZSoloActiveScreen(state: s)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'سیب');
      await tester.tap(find.bySemanticsLabel('بفرست'));
      await tester.pump();
      expect(bloc.events.single, isA<WordSubmitted>());
      expect((bloc.events.single as WordSubmitted).word, 'سیب');
    });

    testWidgets('back button asks before ending the game', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.bySemanticsLabel('بازگشت'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('پایان بازی؟'), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('urgent timer / slot pulse schedule no frames', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(
          _state(words: _chain.take(2).toList(), time: 3),
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];
    for (final brightness in Brightness.values) {
      for (final size in sizes) {
        testWidgets('no overflow ${size.width.toInt()}×${size.height.toInt()} '
            '${brightness.name}', (tester) async {
          await _size(tester, size.width, size.height);
          for (final s in [
            _state(),
            _state(
              mode: 'daily',
              words: _chain,
              scores: _scores,
              next: 'ه',
              score: 9999,
              time: 3,
              mistake: 'x',
            ),
          ]) {
            await tester.pumpWidget(_screen(s, brightness: brightness));
            await tester.pump(const Duration(milliseconds: 700));
            expect(tester.takeException(), isNull);
          }
        });
      }
    }

    testWidgets('keyboard open on a small phone: still no overflow', (
      tester,
    ) async {
      await _size(tester, 375, 667);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        _screen(
          _state(words: _chain.take(4).toList(), scores: _scores, next: 'ب'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });
  });

  goldens();

  group('contrast (≥ 4.5:1 for text)', () {
    for (final entry
        in {
          'light': (ZColors.light, ZScene.light),
          'dark': (ZColors.dark, ZScene.dark),
        }.entries) {
      test('${entry.key}: ink on tile and chips', () {
        final (z, zs) = entry.value;
        // Word tile letters.
        for (final ink in [
          zs.coralInk,
          zs.tealInk,
          zs.indigoInk,
          zs.amberInk,
        ]) {
          expect(
            _contrast(ink, zs.tile),
            greaterThanOrEqualTo(4.5),
            reason: '$ink',
          );
        }
        expect(_contrast(z.ink, zs.tile), greaterThanOrEqualTo(4.5));
        // HUD text on surface.
        expect(_contrast(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(zs.coralInk, z.surface), greaterThanOrEqualTo(4.5));
        // Points pill, badges, mistake banner, slot label.
        expect(
          _contrast(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(_contrast(zs.coralInk, z.tintCoral), greaterThanOrEqualTo(4.5));
        // Letter tile (large text, 3:1).
        expect(_contrast(z.onTeal, z.teal), greaterThanOrEqualTo(3));
      });
    }
  });
}

class _GoldenHost extends StatelessWidget {
  final Widget child;
  const _GoldenHost(this.child);

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: const Key('golden'), child: child);
}

void goldens() {
  testWidgets('golden daily light (word cap subtitle, no toggle)', (
    tester,
  ) async {
    await _size(tester, 393, 852);
    final s = _state(
      mode: 'daily',
      words: _chain.take(3).toList(),
      scores: _scores,
      next: 'ک',
      score: 110,
      time: 9,
    );
    await tester.pumpWidget(_GoldenHost(_screen(s, reduceMotion: true)));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/z_solo_daily_light.png'),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('golden mid-game ${brightness.name}', (tester) async {
      await _size(tester, 393, 852);
      final s = _state(
        words: _chain.take(9).toList(),
        scores: _scores,
        next: 'ه',
        score: 740,
        time: 4,
        lives: 1,
        counts: const {},
      );
      await tester.pumpWidget(
        _GoldenHost(_screen(s, brightness: brightness, reduceMotion: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/z_solo_mid_${brightness.name}.png'),
      );
    });
  }
}
