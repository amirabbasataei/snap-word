import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/view/z_play_screen.dart';

import '../../helpers/z_test_app.dart';

class _FakeAuth extends Fake implements AuthCubit {
  final AuthState current;
  _FakeAuth(this.current);

  @override
  AuthState get state => current;

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

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

/// A shared chain: the player opens, the AI answers, alternating.
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

GameActive _state({
  String opponent = 'ai_medium',
  int words = 0,
  List<int> scores = const [],
  String? next,
  int score = 0,
  int opponentScore = 0,
  int time = 15,
  bool myTurn = true,
  Map<String, int> counts = const {},
}) {
  final chain = _chain.take(words).toList();
  return GameActive(
    localMatchId: 1,
    mode: 'classic',
    opponentType: opponent,
    wordChain: chain,
    wordScores: scores,
    score: score,
    streak: 0,
    turnTimeRemaining: time,
    nextStartLetter: next,
    guestHintUsesLeft: 5,
    continueUsed: false,
    isMyTurn: myTurn,
    opponentScore: opponentScore,
    wordOwners: [
      for (var i = 0; i < chain.length; i++) i.isEven ? 'player' : 'ai',
    ],
    powerupCounts: counts,
  );
}

Widget _screen(
  GameActive s, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  GameBloc? bloc,
}) => BlocProvider<GameBloc>.value(
  value: bloc ?? _FakeGame(),
  child: zTestApp(
    Builder(
      builder:
          (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: ZPlayActiveScreen(state: s),
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
    GetIt.I.registerSingleton<AuthCubit>(_FakeAuth(const AuthGuest()));
  });
  tearDown(() => GetIt.I.reset());

  group('avatarInitial', () {
    test('first letter of the name, ت for guests / non-letters', () {
      expect(avatarInitial('امیر'), 'ا');
      expect(avatarInitial('  sara'), 'S');
      expect(avatarInitial(null), 'ت');
      expect(avatarInitial(''), 'ت');
      expect(avatarInitial('_x'), 'ت');
      expect(avatarInitial('۱۲۳'), 'ت');
    });
  });

  group('states', () {
    testWidgets('empty chain, your turn: start chip, cue slot, level chips', (
      tester,
    ) async {
      await _size(tester, 430, 932);
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('شروع زنجیر'), findsOneWidget);
      expect(find.text('اولین کلمه رو بنویس'), findsOneWidget);
      expect(find.text('نوبت تو'), findsOneWidget);
      expect(find.text('حریف هوشمند · متوسط'), findsOneWidget);
      expect(find.text('۷ حرف به بالا = دوبرابر'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // Guest avatar disc.
      expect(find.widgetWithText(ZDiscAvatar, 'ت'), findsOneWidget);
    });

    testWidgets('signed-in avatar shows the username initial', (tester) async {
      await _size(tester, 430, 932);
      GetIt.I.unregister<AuthCubit>();
      GetIt.I.registerSingleton<AuthCubit>(
        _FakeAuth(const AuthAuthenticated(userId: 'u', username: 'Maryam')),
      );
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.widgetWithText(ZDiscAvatar, 'M'), findsOneWidget);
    });

    testWidgets('mid-game: bubbles, my points only, both scores, turn', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(
          _state(
            words: 5,
            scores: [30, 40, 50],
            next: 'ف',
            score: 120,
            opponentScore: 80,
            time: 9,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (final w in _chain.take(5)) {
        expect(find.bySemanticsLabel(w), findsOneWidget, reason: w);
      }
      // Words 1, 3 and 5 are mine: three points pills, none on the AI's.
      expect(find.text('+۳۰'), findsOneWidget);
      expect(find.text('+۴۰'), findsOneWidget);
      expect(find.text('+۵۰'), findsOneWidget);
      expect(find.text('۱۲۰'), findsOneWidget);
      expect(find.text('۸۰'), findsOneWidget);
      expect(find.text('۰۹'), findsOneWidget);
      expect(find.text('حالا با «ف»'), findsOneWidget);
      expect(find.bySemanticsLabel('۹ ثانیه'), findsOneWidget);
    });

    testWidgets('level dots follow the opponent level', (tester) async {
      await _size(tester, 393, 852);
      for (final (type, label, tier) in [
        ('ai_easy', 'آسان', '۱'),
        ('ai_hard', 'سخت', '۳'),
      ]) {
        await tester.pumpWidget(_screen(_state(opponent: type)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('حریف هوشمند · $label'), findsOneWidget);
        expect(
          find.bySemanticsLabel('حریف هوشمند · $label، سطح $tier از ۳'),
          findsOneWidget,
        );
      }
    });

    testWidgets('opponent thinking: turn chip, no field, paused ring', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 3, next: 'ک', myTurn: false)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('نوبت حریف'), findsOneWidget);
      expect(find.text('نوبت تو'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('حریف هوشمند در حال فکر کردن…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('power-ups: hint, extra time, shield', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('راهنما'), findsOneWidget);
      expect(find.text('وقت بیشتر'), findsOneWidget);
      expect(find.text('سپر'), findsOneWidget);
    });

    testWidgets('typing and sending a word dispatches WordSubmitted', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      final bloc = _FakeGame();
      await tester.pumpWidget(_screen(_state(next: 'س'), bloc: bloc));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'سیب');
      await tester.tap(find.bySemanticsLabel('بفرست'));
      await tester.pump();
      expect((bloc.events.single as WordSubmitted).word, 'سیب');
    });

    testWidgets('long-word tag appears from seven letters', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(_screen(_state(next: 'س')));
      await tester.pump(const Duration(milliseconds: 100));
      double tagOpacity() =>
          tester
              .widget<AnimatedOpacity>(
                find.ancestor(
                  of: find.text('۷ حرف · دوبرابر'),
                  matching: find.byType(AnimatedOpacity),
                ),
              )
              .opacity;
      expect(tagOpacity(), 0);
      await tester.enterText(find.byType(TextField), 'سرگرمی');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tagOpacity(), 0);
      await tester.enterText(find.byType(TextField), 'سرگرمیها');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tagOpacity(), 1);
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
    testWidgets('your turn: nothing schedules frames', (tester) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 2, time: 3), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('opponent thinking: no spinner, nothing animates', (
      tester,
    ) async {
      await _size(tester, 393, 852);
      await tester.pumpWidget(
        _screen(_state(words: 3, myTurn: false), reduceMotion: true),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CircularProgressIndicator), findsNothing);
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
              opponent: 'ai_hard',
              words: 10,
              scores: [30, 40, 50, 60, 70],
              next: 'ه',
              score: 99999,
              opponentScore: 88888,
              time: 3,
            ),
            _state(words: 4, next: 'ب', myTurn: false, score: 1200),
          ]) {
            await tester.pumpWidget(_screen(s, brightness: brightness));
            await tester.pump(const Duration(milliseconds: 700));
            expect(tester.takeException(), isNull);
          }
        });
      }
    }

    testWidgets('keyboard open on a small phone, long word tag: no overflow', (
      tester,
    ) async {
      await _size(tester, 375, 667);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(_screen(_state(words: 6, next: 'ب')));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.enterText(find.byType(TextField), 'سرگرمیهای');
      await tester.pump(const Duration(milliseconds: 300));
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
      test('${entry.key}: header, bubbles, chips, tags', () {
        final (z, zs) = entry.value;
        // Scores / labels / level chip / slot label on surface.
        expect(_contrast(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        // Word letters on the player's tile bubble and the AI's surface one.
        expect(_contrast(z.ink, zs.tile), greaterThanOrEqualTo(4.5));
        for (final ink in [
          zs.coralInk,
          zs.tealInk,
          zs.indigoInk,
          zs.amberInk,
        ]) {
          expect(_contrast(ink, zs.tile), greaterThanOrEqualTo(4.5));
          expect(_contrast(ink, z.surface), greaterThanOrEqualTo(4.5));
        }
        // Turn chip, both states.
        expect(
          _contrast(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        // Bonus chip and long-word tag.
        expect(_contrast(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        // Timer number (calm ring) on its core, and the coral urgent one.
        expect(_contrast(zs.coralInk, z.surface), greaterThanOrEqualTo(4.5));
        // Player initial on the indigo disc (large text, 3:1).
        expect(_contrast(z.onIndigo, z.indigo), greaterThanOrEqualTo(3));
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
  for (final brightness in Brightness.values) {
    testWidgets('golden mid-game ${brightness.name}', (tester) async {
      await _size(tester, 393, 852);
      final s = _state(
        words: 5,
        scores: [30, 40, 40],
        next: 'ف',
        score: 320,
        opponentScore: 290,
        time: 8,
      );
      await tester.pumpWidget(
        _GoldenHost(_screen(s, brightness: brightness, reduceMotion: true)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await expectLater(
        find.byKey(const Key('golden')),
        matchesGoldenFile('goldens/z_play_mid_${brightness.name}.png'),
      );
    });
  }

  testWidgets('golden opponent thinking dark', (tester) async {
    await _size(tester, 393, 852);
    final s = _state(
      opponent: 'ai_hard',
      words: 4,
      scores: [30, 40],
      next: 'ب',
      score: 70,
      opponentScore: 90,
      myTurn: false,
    );
    await tester.pumpWidget(
      _GoldenHost(_screen(s, brightness: Brightness.dark, reduceMotion: true)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/z_play_thinking_dark.png'),
    );
  });
}
