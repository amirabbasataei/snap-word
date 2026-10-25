import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/daily/view/daily_board_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_podium.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_rows.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_self_row.dart';

import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

/// Friday 2026-10-16 15:30 in Iran: 8 h 30 min to the day's end.
DateTime _now() => DateTime.utc(2026, 10, 16, 12);

class _Auth extends FakeAuthCubit {
  _Auth()
    : super(
        const AuthAuthenticated(userId: 'me-1', username: 'آرش', coins: 90),
      );

  @override
  bool get isGuest => false;
}

LeaderboardEntry _e(int rank, String id, String name, int score, int chain) =>
    LeaderboardEntry(
      userId: id,
      username: name,
      score: score,
      rank: rank,
      chainLength: chain,
    );

LeaderboardResult _board({
  int players = 8,
  int? myRank = 5,
  int? myScore = 280,
  String name = 'بازیکن',
  int score = 480,
}) => LeaderboardResult(
  entries: [
    for (var i = 0; i < players; i++)
      _e(
        i + 1,
        i == 4 ? 'me-1' : 'u$i',
        i == 4 ? 'آرش' : '$name $i',
        score - i * 20,
        20 - i,
      ),
  ],
  playerRank: myRank ?? 0,
  playerScore: myScore,
  dayNumber: 42,
);

class _Boards extends Fake implements LeaderboardRepository {
  LeaderboardResult result = _board();
  Object? error;
  Completer<LeaderboardResult>? gate;
  final asked = <String>[];

  @override
  Future<LeaderboardResult> fetchDaily(String currentUserId) async {
    asked.add(currentUserId);
    final g = gate;
    if (g != null) return g.future;
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

class _Harness {
  final repo = _Boards();
  final visited = <String>[];

  Future<void> register() async {
    GetIt.I
      ..registerSingleton<AuthCubit>(_Auth())
      ..registerSingleton<LeaderboardRepository>(repo);
  }

  Widget app({
    String initial = '/daily/board',
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) {
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/daily/board',
          builder: (_, _) => DailyBoardScreen(clock: _now),
        ),
        GoRoute(
          path: '/daily',
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => context.push('/daily/board'),
                  child: const Text('open board'),
                ),
              ),
        ),
        GoRoute(
          path: '/home',
          builder: (_, state) {
            visited.add(state.uri.toString());
            return const Scaffold(body: Text('home'));
          },
        ),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
    );
  }
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(loadVazirmatn);

  late _Harness h;

  setUp(() async {
    await GetIt.I.reset();
    h = _Harness();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> open(
    WidgetTester tester, {
    String initial = '/daily/board',
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double w = 393,
    double hgt = 852,
  }) async {
    _size(tester, w, hgt);
    await h.register();
    await tester.pumpWidget(
      h.app(initial: initial, brightness: brightness, textScale: textScale),
    );
    await _settle(tester);
  }

  group('states', () {
    testWidgets('loading: the mascot card', (tester) async {
      h.repo.gate = Completer();
      await open(tester);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(h.repo.asked, ['me-1'], reason: 'asks for the signed-in player');
    });

    testWidgets('failure: the message and a working retry', (tester) async {
      h.repo.error = const LeaderboardException(
        'بارگذاری جدول امروز ناموفق بود',
      );
      await open(tester);
      expect(find.text('بارگذاری جدول امروز ناموفق بود'), findsOneWidget);
      h.repo.error = null;
      await tester.tap(find.text(ZLoadState.retryLabel));
      await _settle(tester);
      expect(find.byType(BoardPodium), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('empty: nobody played, and a way back to the challenge', (
      tester,
    ) async {
      h.repo.result = const LeaderboardResult(
        entries: [],
        playerRank: 0,
        dayNumber: 42,
      );
      await open(tester);
      expect(find.byType(ZEmptyState), findsOneWidget);
      expect(find.text('امروز هنوز کسی بازی نکرده'), findsOneWidget);
      await tester.tap(find.text('بازگشت به چالش'));
      await _settle(tester);
      expect(h.visited, ['/home'], reason: 'nothing underneath → home');
    });

    testWidgets('a full board: note, podium, rows, own row', (tester) async {
      await open(tester);
      expect(find.text('جدول امروز'), findsOneWidget);
      expect(find.text('چالش روزانهٔ شمارهٔ ۴۲'), findsOneWidget);
      expect(find.text('جایزهٔ سه نفر اول: ۱۰۰ · ۶۰ · ۳۰ سکه'), findsOneWidget);
      expect(find.text('همهٔ شرکت‌کننده‌ها ۱۰ سکه می‌گیرند'), findsOneWidget);
      expect(
        find.textContaining('پایان امروز: ۸ ساعت و ۳۰ دقیقه'),
        findsOneWidget,
      );
      expect(find.byType(BoardPodium), findsOneWidget);
      expect(find.byType(BoardRowsCard), findsOneWidget);
      expect(
        find.text('زنجیر ۱۶ کلمه'),
        findsOneWidget,
        reason: 'chain_length',
      );
      expect(find.text('تو — آرش'), findsOneWidget);
      expect(find.text('۲۸۰'), findsWidgets, reason: 'own score');
      expect(find.text('۱٬۲۳۴'), findsNothing);
    });

    testWidgets('fewer than three players: no podium', (tester) async {
      h.repo.result = _board(players: 2, myRank: 2, myScore: 460);
      await open(tester);
      expect(find.byType(BoardPodium), findsNothing);
      expect(find.byType(BoardRowsCard), findsOneWidget);
    });

    testWidgets('played but outside the top 100: rank without a score', (
      tester,
    ) async {
      h.repo.result = _board(myRank: 140, myScore: null);
      await open(tester);
      expect(find.text('۱۴۰'), findsOneWidget);
      final self = find.byType(BoardSelfRow);
      expect(
        find.descendant(of: self, matching: find.textContaining('امتیاز')),
        findsNothing,
      );
    });

    testWidgets('has not played today: the own row says so', (tester) async {
      h.repo.result = _board(myRank: null, myScore: null);
      await open(tester);
      expect(
        find.text('امروز هنوز چالش روزانه را بازی نکرده‌ای'),
        findsOneWidget,
      );
    });
  });

  group('navigation', () {
    testWidgets('back pops to the screen that pushed it', (tester) async {
      await open(tester, initial: '/daily');
      await tester.tap(find.text('open board'));
      await _settle(tester);
      expect(find.byType(BoardPodium), findsOneWidget);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(find.text('open board'), findsOneWidget);
    });

    testWidgets('back with nothing underneath goes home', (tester) async {
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(h.visited, ['/home']);
    });
  });

  group('layout', () {
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
            'every state: no overflow ${size.width.toInt()}×${size.height.toInt()} ${brightness.name} ×$scale',
            (tester) async {
              Future<void> check(String reason) async {
                expect(tester.takeException(), isNull, reason: reason);
                for (final list in [
                  find.byType(ListView),
                  find.byType(SingleChildScrollView),
                ]) {
                  if (list.evaluate().isNotEmpty) {
                    await tester.drag(list.first, const Offset(0, -3000));
                    await tester.pump();
                    expect(
                      tester.takeException(),
                      isNull,
                      reason: '$reason scrolled',
                    );
                  }
                }
              }

              Future<void> fresh(void Function(_Boards r) setUpRepo) async {
                await GetIt.I.reset();
                h = _Harness();
                setUpRepo(h.repo);
                await open(
                  tester,
                  brightness: brightness,
                  textScale: scale,
                  w: size.width,
                  hgt: size.height,
                );
              }

              const long = 'یک_نام_کاربری_خیلی_خیلی_بلند_فارسی_برای_جدول';
              await fresh((r) => r.gate = Completer());
              await check('loading');
              await fresh(
                (r) =>
                    r.error = const LeaderboardException(
                      'بارگذاری جدول امروز ناموفق بود',
                    ),
              );
              await check('error');
              await fresh(
                (r) =>
                    r.result = const LeaderboardResult(
                      entries: [],
                      playerRank: 0,
                    ),
              );
              await check('empty');
              await fresh((r) => r.result = _board(name: long, score: 999999));
              await check('busy board');
              await fresh(
                (r) =>
                    r.result = _board(players: 2, myRank: 2, myScore: 999999),
              );
              await check('two players');
              await fresh(
                (r) => r.result = _board(myRank: 123456, myScore: null),
              );
              await check('rank only');
            },
          );
        }
      }
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    testWidgets('board light', (tester) async {
      await open(tester);
      await shot(tester, 'daily_board_light');
    });

    testWidgets('board small phone dark', (tester) async {
      await open(tester, brightness: Brightness.dark, w: 320, hgt: 568);
      await shot(tester, 'daily_board_320_dark');
    });

    testWidgets('empty light', (tester) async {
      h.repo.result = const LeaderboardResult(entries: [], playerRank: 0);
      await open(tester);
      await shot(tester, 'daily_board_empty_light');
    });
  });
}
