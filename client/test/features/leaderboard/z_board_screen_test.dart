import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_note.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_podium.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_rows.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_self_row.dart';
import 'package:wordchain/features/leaderboard/view/widgets/board_tabs.dart';
import 'package:wordchain/features/leaderboard/view/z_board_screen.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _signedIn = AuthAuthenticated(
  userId: 'me-1',
  username: 'آرش',
  coins: 1240,
);

/// Sunday 2026-10-25 15:30 in Iran: 5 days 8.5 h to the weekly reset, 8.5 h to
/// the Daily Challenge's midnight.
DateTime _now() => DateTime.utc(2026, 10, 25, 12);

LeaderboardEntry _e(
  int rank,
  String id,
  String name,
  int score, {
  String? avatar,
  int? chain,
}) => LeaderboardEntry(
  userId: id,
  username: name,
  score: score,
  rank: rank,
  avatarId: avatar,
  chainLength: chain,
);

const _names = [
  'نوید ا.',
  'پریسا',
  'حسین ط.',
  'مریم ک.',
  'آرش',
  'سینا ر.',
  'زهرا ب.',
  'کامران د.',
  'لیلا م.',
  'بهنام ص.',
  'ندا ف.',
  'امیر ج.',
];

/// Twelve players; the signed-in player («آرش», `me-1`) is 5th.
LeaderboardResult _weekly({int? rank, int? score}) => LeaderboardResult(
  entries: [
    for (var i = 0; i < _names.length; i++)
      _e(
        i + 1,
        i == 4 ? 'me-1' : 'u$i',
        _names[i],
        5360 - i * 310,
        avatar: i == 1 ? 'fox' : null,
      ),
  ],
  playerRank: rank ?? 5,
  playerScore: score ?? 3750,
);

LeaderboardResult _allTime() => LeaderboardResult(
  entries: [
    _e(1, 'u0', 'نوید ا.', 91000),
    _e(2, 'me-1', 'آرش', 74000),
    _e(3, 'u2', 'حسین ط.', 5000),
    _e(4, 'u3', 'مریم ک.', 4000),
  ],
  playerRank: 2,
  playerScore: 74000,
);

LeaderboardResult _daily({bool me = false, int rank = 14}) => LeaderboardResult(
  entries: [
    _e(1, 'u0', 'نوید ا.', 480, chain: 20),
    _e(2, 'u1', 'پریسا', 410, chain: 17),
    _e(3, 'u2', 'حسین ط.', 390, chain: 16),
    _e(4, 'u3', 'مریم ک.', 300, chain: 12),
    if (me) _e(5, 'me-1', 'آرش', 280, chain: 11),
  ],
  playerRank: me ? 5 : rank,
  playerScore: me ? 280 : null,
  dayNumber: 42,
);

LeaderboardResult _friends() => LeaderboardResult(
  entries: [
    _e(1, 'f1', 'مریم ک.', 900),
    _e(2, 'me-1', 'آرش', 300),
    _e(3, 'f2', 'حسین ط.', 0),
  ],
  playerRank: 2,
  playerScore: 300,
);

class _Auth extends FakeAuthCubit {
  _Auth(super.state);

  @override
  bool get isGuest => current is! AuthAuthenticated;
}

class _FakeBoards extends Fake implements LeaderboardRepository {
  final results = <BoardTab, LeaderboardResult>{
    BoardTab.weekly: _weekly(),
    BoardTab.daily: _daily(),
    BoardTab.allTime: _allTime(),
    BoardTab.friends: _friends(),
  };
  final errors = <BoardTab, Object>{};
  final gates = <BoardTab, Completer<LeaderboardResult>>{};
  final calls = <BoardTab>[];

  Future<LeaderboardResult> _go(BoardTab tab) async {
    calls.add(tab);
    final gate = gates[tab];
    if (gate != null) return gate.future;
    final error = errors[tab];
    if (error != null) throw error;
    return results[tab]!;
  }

  @override
  Future<LeaderboardResult> fetchGlobal() => _go(BoardTab.weekly);

  @override
  Future<LeaderboardResult> fetchAllTime() => _go(BoardTab.allTime);

  @override
  Future<LeaderboardResult> fetchDaily(String currentUserId) =>
      _go(BoardTab.daily);

  @override
  Future<LeaderboardResult> fetchFriends(String currentUserId) =>
      _go(BoardTab.friends);

  int count(BoardTab t) => calls.where((c) => c == t).length;
}

class _Harness {
  final repo = _FakeBoards();
  final bus = TabRefreshBus();
  final routes = <String>[];

  Future<void> register({AuthState state = _signedIn}) async {
    GetIt.I
      ..registerSingleton<AuthCubit>(_Auth(state))
      ..registerSingleton<LeaderboardRepository>(repo)
      ..registerSingleton<TabRefreshBus>(bus);
  }

  Widget app({
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
  }) {
    final router = GoRouter(
      initialLocation: '/leaderboard',
      routes: [
        GoRoute(
          path: '/leaderboard',
          builder: (_, _) => const ZBoardScreen(clock: _now),
        ),
        for (final path in ['/login', '/daily', '/friends'])
          GoRoute(
            path: path,
            builder: (_, state) {
              routes.add(state.uri.toString());
              return Scaffold(body: Text(path));
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
              disableAnimations: reduceMotion,
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
    AuthState auth = _signedIn,
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
    double w = 393,
    double hgt = 852,
  }) async {
    _size(tester, w, hgt);
    await h.register(state: auth);
    await tester.pumpWidget(
      h.app(
        brightness: brightness,
        reduceMotion: reduceMotion,
        textScale: textScale,
      ),
    );
    await _settle(tester);
  }

  Future<void> goTo(WidgetTester tester, String tab) async {
    await tester.tap(find.text(tab));
    await _settle(tester);
  }

  double scaleOf(WidgetTester tester, Finder f) =>
      tester.renderObject<RenderParagraph>(f.first).textScaler.scale(10);

  group('weekly (the default tab)', () {
    testWidgets('title, the four tabs, podium, rows and my row', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.text('جدول'), findsOneWidget);
      for (final label in ['این هفته', 'امروز', 'همیشه', 'دوستان']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byType(BoardPodium), findsOneWidget);
      // Podium: 1st, 2nd, 3rd.
      for (final name in ['نوید ا.', 'پریسا', 'حسین ط.']) {
        expect(
          find.descendant(
            of: find.byType(BoardPodium),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }
      // The rest are rows, from 4th on.
      expect(find.byType(BoardRow, skipOffstage: false), findsNWidgets(9));
      expect(find.text('مریم ک.'), findsOneWidget);
      expect(find.text('۴٬۴۳۰'), findsOneWidget);
      // Own row, pinned, from the server's rank/score.
      expect(find.text('تو — آرش'), findsOneWidget);
      expect(find.text('جزو ده نفر برتری!'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.text('۵'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.text('۳٬۷۵۰'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(h.repo.calls, [BoardTab.weekly]);
    });

    testWidgets('the note states the real prizes and the reset countdown', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.text('جایزهٔ سه نفر اول: ۵۰۰ · ۳۰۰ · ۱۰۰ سکه'),
        findsOneWidget,
      );
      expect(
        find.text('جدول تا ۵ روز و ۸ ساعت دیگر بازنشانی می‌شود'),
        findsOneWidget,
      );
    });

    testWidgets('what nothing backs stays out', (tester) async {
      await open(tester);
      for (final omitted in [
        'بلندترین زنجیر',
        'لیگ',
        'نفر این هفته',
        'بازیکن',
        'آنلاین',
      ]) {
        expect(find.textContaining(omitted), findsNothing);
      }
      // Weekly rows have no sub-line: that field exists on the daily board only.
      expect(find.textContaining('زنجیر'), findsNothing);
    });

    testWidgets(
      'a premium avatar id reaches the disc; others keep the initial',
      (tester) async {
        await open(tester);
        final discs =
            tester.widgetList<ZDiscAvatar>(find.byType(ZDiscAvatar)).toList();
        expect(discs.where((d) => d.avatarId == 'fox'), hasLength(1));
        expect(discs.where((d) => d.avatarId == null), isNotEmpty);
      },
    );

    testWidgets('my rank outside the top 100: still shown, with the gap', (
      tester,
    ) async {
      h.repo.results[BoardTab.weekly] = _weekly(rank: 340, score: 800);
      await open(tester);
      expect(find.text('۳۳۰ پله تا ده‌تای اول'), findsOneWidget);
      expect(find.text('۳۴۰'), findsOneWidget);
      expect(find.text('۸۰۰'), findsOneWidget);
    });

    testWidgets('my own row in the list is marked; others are not', (
      tester,
    ) async {
      final z = AppTheme.light.extension<ZColors>()!;
      h.repo.results[BoardTab.weekly] = _weekly();
      // Rank 5 is in the rows card (the podium holds 1–3).
      await open(tester);
      final tinted = find.descendant(
        of: find.byType(BoardRowsCard),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == z.tintIndigo,
        ),
      );
      expect(tinted, findsOneWidget);
      expect(
        find.descendant(of: tinted, matching: find.text('آرش')),
        findsOneWidget,
      );
    });

    testWidgets('my place on the podium carries a «تو» tag', (tester) async {
      h.repo.results[BoardTab.weekly] = LeaderboardResult(
        entries: [
          _e(1, 'u0', 'نوید ا.', 900),
          _e(2, 'me-1', 'آرش', 800),
          _e(3, 'u2', 'حسین ط.', 700),
        ],
        playerRank: 2,
        playerScore: 800,
      );
      await open(tester);
      expect(
        find.descendant(
          of: find.byType(BoardPodium),
          matching: find.text('تو'),
        ),
        findsOneWidget,
      );
      // Exactly three entries: all on the podium, no list under it.
      expect(find.byType(BoardRowsCard), findsNothing);
    });

    testWidgets('not ranked this week: «—» and what to do', (tester) async {
      h.repo.results[BoardTab.weekly] = LeaderboardResult(
        entries: _weekly().entries,
        playerRank: 0,
        playerScore: 0,
      );
      await open(tester);
      expect(
        find.text('این هفته امتیازی نداری — یک بازی آنلاین بازی کن'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      // No score is shown for an unranked player, and the copy no longer
      // promises that the Daily Challenge counts here.
      expect(find.textContaining('چالش روزانه'), findsNothing);
    });

    testWidgets('one or two players: no podium, a plain list', (tester) async {
      h.repo.results[BoardTab.weekly] = LeaderboardResult(
        entries: [_e(1, 'u0', 'نوید ا.', 900), _e(2, 'me-1', 'آرش', 800)],
        playerRank: 2,
        playerScore: 800,
      );
      await open(tester);
      expect(find.byType(BoardPodium), findsNothing);
      expect(find.byType(BoardRow), findsNWidgets(2));
      expect(find.text('نوید ا.'), findsOneWidget);
    });

    testWidgets('empty board: a mascot card, no list and no self row', (
      tester,
    ) async {
      h.repo.results[BoardTab.weekly] = const LeaderboardResult(
        entries: [],
        playerRank: 0,
        playerScore: 0,
      );
      await open(tester);
      expect(find.text('هنوز کسی امتیاز نگرفته'), findsOneWidget);
      expect(find.byType(ZEmptyState), findsOneWidget);
      expect(find.byType(BoardSelfRow), findsNothing);
      expect(find.byType(BoardPodium), findsNothing);
    });
  });

  group('loading and failing', () {
    testWidgets('loading: the thinking mascot, then the list', (tester) async {
      final gate = h.repo.gates[BoardTab.weekly] = Completer();
      await open(tester);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The frame is already there.
      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.byType(BoardTabs), findsOneWidget);
      gate.complete(_weekly());
      await _settle(tester);
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.byType(BoardPodium), findsOneWidget);
    });

    testWidgets('a failed load: the Persian reason and a working retry', (
      tester,
    ) async {
      h.repo.errors[BoardTab.weekly] = const LeaderboardException(
        loadLeaderboardFailedMessage,
      );
      await open(tester);
      expect(find.text(loadLeaderboardFailedMessage), findsOneWidget);
      expect(find.text(ZLoadState.retryLabel), findsOneWidget);
      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.sad,
      );

      h.repo.errors.clear();
      await tester.tap(find.text(ZLoadState.retryLabel));
      await _settle(tester);
      expect(find.byType(BoardPodium), findsOneWidget);
      expect(find.text(loadLeaderboardFailedMessage), findsNothing);
      expect(h.repo.count(BoardTab.weekly), 2);
    });

    testWidgets('an unexpected error shows the generic Persian message', (
      tester,
    ) async {
      h.repo.errors[BoardTab.weekly] = StateError('boom');
      await open(tester);
      expect(find.text(loadLeaderboardFailedMessage), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });

    testWidgets('one failing tab does not take the others down', (
      tester,
    ) async {
      h.repo.errors[BoardTab.daily] = const LeaderboardException(
        loadDailyBoardFailedMessage,
      );
      await open(tester);
      await goTo(tester, 'امروز');
      expect(find.text(loadDailyBoardFailedMessage), findsOneWidget);
      await goTo(tester, 'این هفته');
      expect(find.byType(BoardPodium), findsOneWidget);
      expect(find.text(loadDailyBoardFailedMessage), findsNothing);
      await goTo(tester, 'همیشه');
      expect(find.byType(BoardPodium), findsOneWidget);

      h.repo.errors.clear();
      await goTo(tester, 'امروز');
      expect(find.text('چالش روزانهٔ شمارهٔ ۴۲'), findsOneWidget);
    });
  });

  group('tabs', () {
    testWidgets('each tab loads on its first visit and shows its board', (
      tester,
    ) async {
      await open(tester);
      expect(h.repo.calls, [BoardTab.weekly]);

      await goTo(tester, 'امروز');
      expect(h.repo.calls, [BoardTab.weekly, BoardTab.daily]);
      expect(find.text('چالش روزانهٔ شمارهٔ ۴۲'), findsOneWidget);

      await goTo(tester, 'همیشه');
      expect(h.repo.count(BoardTab.allTime), 1);
      expect(find.text('مجموع امتیاز بازی‌های آنلاین'), findsOneWidget);
      expect(find.text('۹۱٬۰۰۰'), findsOneWidget);

      await goTo(tester, 'دوستان');
      expect(h.repo.count(BoardTab.friends), 1);
      expect(find.text('امتیاز این هفتهٔ تو و دوستانت'), findsOneWidget);

      await goTo(tester, 'این هفته');
      expect(find.text('نوید ا.'), findsOneWidget);
    });

    testWidgets('switching back shows the old board at once while refreshing', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'امروز');
      final gate = h.repo.gates[BoardTab.weekly] = Completer();
      await tester.tap(find.text('این هفته'));
      await tester.pump();
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.byType(BoardPodium), findsOneWidget);
      gate.complete(_weekly());
      await _settle(tester);
      expect(find.byType(BoardPodium), findsOneWidget);
    });

    testWidgets('the selected segment is announced as selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('این هفته')),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('امروز')),
        isSemantics(isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('daily: chain length on rows, day number, prizes, countdown', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'امروز');
      expect(find.text('چالش روزانهٔ شمارهٔ ۴۲'), findsOneWidget);
      expect(find.text('جایزهٔ سه نفر اول: ۱۰۰ · ۶۰ · ۳۰ سکه'), findsOneWidget);
      expect(find.text('پایان امروز: ۸ ساعت و ۳۰ دقیقه دیگر'), findsOneWidget);
      // Rank 4 is a row, with the canvas's sub-line from the real field.
      expect(find.text('زنجیر ۱۲ کلمه'), findsOneWidget);
      expect(find.text('مریم ک.'), findsOneWidget);
    });

    testWidgets('daily: my rank without a score shows no score', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'امروز');
      expect(find.text('۴ پله تا ده‌تای اول'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.text('۱۴'),
        ),
        findsOneWidget,
      );
      // Only the rank bead and the name are there: no score text in the row.
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.byType(Text),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('daily: my own entry gives the score', (tester) async {
      h.repo.results[BoardTab.daily] = _daily(me: true);
      await open(tester);
      await goTo(tester, 'امروز');
      expect(
        find.descendant(
          of: find.byType(BoardSelfRow),
          matching: find.text('۲۸۰'),
        ),
        findsOneWidget,
      );
      expect(find.text('جزو ده نفر برتر امروز!'), findsOneWidget);
      // The player's own row in the list carries the chain too.
      expect(find.text('زنجیر ۱۱ کلمه'), findsOneWidget);
    });

    testWidgets(
      'daily: not played yet — a mascot card that opens the challenge',
      (tester) async {
        h.repo.results[BoardTab.daily] = const LeaderboardResult(
          entries: [],
          playerRank: 0,
          dayNumber: 42,
        );
        await open(tester);
        await goTo(tester, 'امروز');
        expect(find.text('امروز هنوز کسی بازی نکرده'), findsOneWidget);
        await tester.tap(find.text('چالش روزانه'));
        await _settle(tester);
        expect(h.routes, ['/daily']);
      },
    );

    testWidgets('all-time: lifetime scores, my rank from the server', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'همیشه');
      expect(find.text('۷۴٬۰۰۰'), findsWidgets);
      expect(find.text('جزو ده نفر برتری!'), findsOneWidget);
    });

    testWidgets('friends: my place among friends, not the global rank', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'دوستان');
      expect(find.text('بین دوستانت نفر ۲'), findsOneWidget);
      expect(find.text('جزو ده نفر برتری!'), findsNothing);
    });

    testWidgets('friends: first place', (tester) async {
      h.repo.results[BoardTab.friends] = LeaderboardResult(
        entries: [_e(1, 'me-1', 'آرش', 900), _e(2, 'f1', 'مریم ک.', 300)],
        playerRank: 1,
        playerScore: 900,
      );
      await open(tester);
      await goTo(tester, 'دوستان');
      expect(find.text('بین دوستانت اولی!'), findsOneWidget);
    });

    testWidgets('friends: nobody scored yet', (tester) async {
      h.repo.results[BoardTab.friends] = LeaderboardResult(
        entries: [_e(1, 'me-1', 'آرش', 0), _e(2, 'f1', 'مریم ک.', 0)],
        playerRank: 1,
        playerScore: 0,
      );
      await open(tester);
      await goTo(tester, 'دوستان');
      expect(
        find.text('این هفته امتیازی نداری — یک بازی آنلاین بازی کن'),
        findsOneWidget,
      );
    });

    testWidgets('friends: no friends yet — the board of one becomes a card', (
      tester,
    ) async {
      h.repo.results[BoardTab.friends] = LeaderboardResult(
        entries: [_e(1, 'me-1', 'آرش', 0)],
        playerRank: 1,
        playerScore: 0,
      );
      await open(tester);
      await goTo(tester, 'دوستان');
      expect(find.text('هنوز دوستی نداری'), findsOneWidget);
      expect(find.byType(BoardSelfRow), findsNothing);
      await tester.tap(find.text('افزودن دوست'));
      await _settle(tester);
      expect(h.routes, ['/friends']);
    });
  });

  group('guest', () {
    testWidgets('a login card; nothing is fetched', (tester) async {
      await open(tester, auth: const AuthGuest());
      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.text('برای دیدن جدول امتیازات، ثبت‌نام کن'), findsOneWidget);
      expect(find.byType(BoardTabs), findsNothing);
      expect(h.repo.calls, isEmpty);
      await tester.tap(find.text('ثبت‌نام رایگان'));
      await _settle(tester);
      expect(h.routes, ['/login?return=/leaderboard']);
    });
  });

  group('refresh on tab tap', () {
    testWidgets('reloads the visible tab silently and keeps the list', (
      tester,
    ) async {
      await open(tester);
      await goTo(tester, 'امروز');
      final gate = h.repo.gates[BoardTab.daily] = Completer();
      h.bus.notify(MainTab.board);
      await tester.pump();
      // No spinner, no blanking: the board stays up while it refreshes.
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.text('چالش روزانهٔ شمارهٔ ۴۲'), findsOneWidget);
      expect(h.repo.count(BoardTab.daily), 2);
      gate.complete(_daily(me: true));
      await _settle(tester);
      expect(find.text('جزو ده نفر برتر امروز!'), findsOneWidget);
      // Only the visible tab was reloaded.
      expect(h.repo.count(BoardTab.weekly), 1);
    });

    testWidgets('a failing refresh keeps the data, no error card', (
      tester,
    ) async {
      await open(tester);
      h.repo.errors[BoardTab.weekly] = const LeaderboardException(
        loadLeaderboardFailedMessage,
      );
      h.bus.notify(MainTab.board);
      await _settle(tester);
      expect(h.repo.count(BoardTab.weekly), 2);
      expect(find.byType(BoardPodium), findsOneWidget);
      expect(find.text(loadLeaderboardFailedMessage), findsNothing);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('taps on other tabs are ignored; a re-tap reloads', (
      tester,
    ) async {
      await open(tester);
      h.bus.notify(MainTab.home);
      h.bus.notify(MainTab.friends);
      h.bus.notify(MainTab.profile);
      await _settle(tester);
      expect(h.repo.calls, [BoardTab.weekly]);
      h.bus.notify(MainTab.board);
      await _settle(tester);
      expect(h.repo.calls, [BoardTab.weekly, BoardTab.weekly]);
    });
  });

  group('motion', () {
    testWidgets('reduced motion: nothing keeps scheduling frames', (
      tester,
    ) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('layout', () {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(430, 932),
    ];

    const longName = 'یک_نام_کاربری_خیلی_خیلی_بلند_فارسی_برای_جدول';

    void busy() {
      LeaderboardResult big(String Function(int) name, {bool chain = false}) =>
          LeaderboardResult(
            entries: [
              for (var i = 0; i < 14; i++)
                _e(
                  i + 1,
                  i == 6 ? 'me-1' : 'u$i',
                  name(i),
                  999999 - i * 11,
                  avatar: i == 1 ? 'fox' : null,
                  chain: chain ? 20 - i : null,
                ),
            ],
            playerRank: 7,
            playerScore: 999999 - 66,
            dayNumber: 365,
          );
      String name(int i) => i % 3 == 0 ? longName : 'بازیکن $i';
      h.repo.results[BoardTab.weekly] = big(name);
      h.repo.results[BoardTab.allTime] = big(name);
      h.repo.results[BoardTab.friends] = big(name);
      h.repo.results[BoardTab.daily] = big(name, chain: true);
    }

    Future<void> visitAll(WidgetTester tester) async {
      for (final tab in ['این هفته', 'امروز', 'همیشه', 'دوستان']) {
        await goTo(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$tab scrolled');
      }
    }

    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        final tag =
            '${size.width.toInt()}×${size.height.toInt()} ${brightness.name}';

        testWidgets('busy boards, every tab: no overflow $tag', (tester) async {
          busy();
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          await visitAll(tester);
        });

        testWidgets('loading, error, empty, guest: no overflow $tag', (
          tester,
        ) async {
          final gate = h.repo.gates[BoardTab.weekly] = Completer();
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          expect(tester.takeException(), isNull);
          gate.complete(_weekly());
          await _settle(tester);

          await GetIt.I.reset();
          h = _Harness();
          h.repo.errors[BoardTab.weekly] = const LeaderboardException(
            loadLeaderboardFailedMessage,
          );
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          expect(tester.takeException(), isNull);

          await GetIt.I.reset();
          h = _Harness();
          h.repo.results[BoardTab.weekly] = const LeaderboardResult(
            entries: [],
            playerRank: 0,
            playerScore: 0,
          );
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          expect(tester.takeException(), isNull);

          await GetIt.I.reset();
          h = _Harness();
          await open(
            tester,
            auth: const AuthGuest(),
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('text ×$scale: no overflow, fixed controls capped at 1.3', (
        tester,
      ) async {
        busy();
        await open(tester, textScale: scale, w: 320, hgt: 568);
        expect(tester.takeException(), isNull);

        // Fixed-height controls keep within 1.3×; the ribbon, the tab labels
        // and the podium.
        expect(scaleOf(tester, find.text('جدول')), lessThanOrEqualTo(13.01));
        expect(
          scaleOf(tester, find.text('این هفته')),
          lessThanOrEqualTo(13.01),
        );
        expect(
          scaleOf(tester, find.textContaining('جایزهٔ سه نفر اول')),
          closeTo(10 * scale, .01),
        );
        final list = find.byType(Scrollable).first;
        final podiumName = find.descendant(
          of: find.byType(BoardPodium),
          matching: find.text('بازیکن 1'),
        );
        await tester.scrollUntilVisible(podiumName, 100, scrollable: list);
        expect(scaleOf(tester, podiumName), lessThanOrEqualTo(13.01));
        // Free text keeps scaling: a list name and the note.
        final rowName = find.descendant(
          of: find.byType(BoardRowsCard),
          matching: find.text('بازیکن 4'),
        );
        await tester.scrollUntilVisible(rowName, 100, scrollable: list);
        expect(scaleOf(tester, rowName), closeTo(10 * scale, .01));
        await visitAll(tester);
      });
    }

    testWidgets('the pinned row is on screen at every size, long name or not', (
      tester,
    ) async {
      busy();
      for (final size in sizes) {
        await GetIt.I.reset();
        h = _Harness();
        busy();
        await open(tester, w: size.width, hgt: size.height);
        final row = tester.getRect(find.byType(BoardSelfRow));
        expect(row.bottom, lessThanOrEqualTo(size.height), reason: '$size');
        expect(row.top, greaterThanOrEqualTo(0), reason: '$size');
      }
    });
  });

  group('note lines', () {
    final now = _now();

    test('weekly: prizes then the reset clock', () {
      expect(BoardNote.lines(BoardTab.weekly, now), [
        'جایزهٔ سه نفر اول: ۵۰۰ · ۳۰۰ · ۱۰۰ سکه',
        'جدول تا ۵ روز و ۸ ساعت دیگر بازنشانی می‌شود',
      ]);
    });

    test('daily: number, prizes, then the time to Iran midnight', () {
      expect(BoardNote.lines(BoardTab.daily, now, dayNumber: 42), [
        'چالش روزانهٔ شمارهٔ ۴۲',
        'جایزهٔ سه نفر اول: ۱۰۰ · ۶۰ · ۳۰ سکه',
        'پایان امروز: ۸ ساعت و ۳۰ دقیقه دیگر',
      ]);
    });

    test('daily: the number is optional', () {
      expect(BoardNote.lines(BoardTab.daily, now).first, 'چالش روزانهٔ امروز');
      expect(
        BoardNote.lines(BoardTab.daily, now, dayNumber: 7).first,
        'چالش روزانهٔ شمارهٔ ۷',
      );
    });

    test('all-time and friends have no prizes or clock', () {
      expect(BoardNote.lines(BoardTab.allTime, now), hasLength(1));
      expect(BoardNote.lines(BoardTab.friends, now), hasLength(1));
    });
  });

  group('contrast', () {
    test('the pairs the board paints, light and dark', () {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        final z = theme.extension<ZColors>()!;
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.onCoral, z.coral), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.tintIndigo), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(z.onInkSurfaceSoft, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    for (final brightness in Brightness.values) {
      testWidgets('weekly ${brightness.name}', (tester) async {
        await open(tester, brightness: brightness);
        await shot(tester, 'z_board_weekly_${brightness.name}');
      });
    }

    testWidgets('weekly small phone dark', (tester) async {
      await open(tester, brightness: Brightness.dark, w: 320, hgt: 568);
      await shot(tester, 'z_board_weekly_320_dark');
    });

    testWidgets('daily light', (tester) async {
      await open(tester, w: 360, hgt: 640);
      await goTo(tester, 'امروز');
      await shot(tester, 'z_board_daily_light');
    });

    testWidgets('friends dark', (tester) async {
      await open(tester, brightness: Brightness.dark);
      await goTo(tester, 'دوستان');
      await shot(tester, 'z_board_friends_dark');
    });

    testWidgets('empty light', (tester) async {
      h.repo.results[BoardTab.weekly] = const LeaderboardResult(
        entries: [],
        playerRank: 0,
        playerScore: 0,
      );
      await open(tester);
      await shot(tester, 'z_board_empty_light');
    });

    testWidgets('error dark', (tester) async {
      h.repo.errors[BoardTab.weekly] = const LeaderboardException(
        loadLeaderboardFailedMessage,
      );
      await open(tester, brightness: Brightness.dark);
      await shot(tester, 'z_board_error_dark');
    });

    testWidgets('guest light', (tester) async {
      await open(tester, auth: const AuthGuest());
      await shot(tester, 'z_board_guest_light');
    });
  });
}
