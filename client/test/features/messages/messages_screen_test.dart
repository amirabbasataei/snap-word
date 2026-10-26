import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/core/widgets/z_accent_disc.dart';
import 'package:wordchain/core/widgets/z_dialog.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_state_card.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';
import 'package:wordchain/features/messages/view/messages_screen.dart';
import 'package:wordchain/features/messages/view/widgets/message_format.dart';
import 'package:wordchain/features/messages/view/widgets/message_tile.dart';
import 'package:wordchain/features/messages/view/widgets/missed_push_tile.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';
import '../rewards/rewards_fakes.dart';

PendingRequest request(String id, String name) =>
    PendingRequest(requesterId: id, username: name);

PendingChallenge challenge(String id, String name) => PendingChallenge(
  id: id,
  challengerId: 'u-$id',
  challengerUsername: name,
  mode: 'classic',
  expiresAt: DateTime.utc(2026, 10, 27),
);

class _Repo extends Fake implements FriendsRepository {
  List<PendingRequest> requests;
  List<PendingChallenge> challenges;
  FriendsException? fetchError;
  FriendsException? respondError;
  Completer<void>? fetchGate;
  Completer<void>? respondGate;
  String? roomOnAccept = 'room-1';
  int fetches = 0;
  final requestAnswers = <(String, bool)>[];
  final challengeAnswers = <(String, bool)>[];

  _Repo({this.requests = const [], this.challenges = const []});

  @override
  Future<List<PendingRequest>> fetchPendingRequests() async {
    fetches++;
    await fetchGate?.future;
    final e = fetchError;
    if (e != null) throw e;
    return List.of(requests);
  }

  @override
  Future<List<PendingChallenge>> fetchPendingChallenges() async =>
      List.of(challenges);

  @override
  Future<void> respondToRequest(String requesterId, bool accept) async {
    await respondGate?.future;
    final e = respondError;
    if (e != null) throw e;
    requestAnswers.add((requesterId, accept));
  }

  @override
  Future<String?> respondToChallenge(String challengeId, bool accept) async {
    await respondGate?.future;
    final e = respondError;
    if (e != null) throw e;
    challengeAnswers.add((challengeId, accept));
    return roomOnAccept;
  }
}

FriendsException _err(String code) =>
    FriendsException(code: code, message: errorMessageFor(code));

/// Signed-in player, or a guest.
class _Auth extends FakeAuthCubit {
  final bool guest;

  _Auth({this.guest = false})
    : super(
        guest
            ? const AuthGuest()
            : const AuthAuthenticated(userId: 'me', username: 'آرش', coins: 90),
      );

  @override
  bool get isGuest => guest;
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

  late _Repo repo;
  final pushed = <GameRouteArgs>[];

  setUp(() async {
    await GetIt.I.reset();
    pushed.clear();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  /// Opens the screen as a pushed route (`/messages` over `/home`).
  Future<void> open(
    WidgetTester tester, {
    _Repo? withRepo,
    bool guest = false,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double w = 393,
    double h = 852,
  }) async {
    _size(tester, w, h);
    repo = withRepo ?? repo;
    final auth = _Auth(guest: guest);
    GetIt.I
      ..registerSingleton<AuthCubit>(auth)
      ..registerSingleton<AdService>(FakeRewardedAds())
      ..registerSingleton<MessagesCubit>(MessagesCubit(repo: repo, auth: auth));
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => context.push('/messages'),
                  child: const Text('open'),
                ),
              ),
        ),
        GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
        GoRoute(
          path: '/game',
          builder: (_, state) {
            pushed.add(state.extra! as GameRouteArgs);
            return const Scaffold(body: Text('game'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
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
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
  }

  _Repo sample() => _Repo(
    requests: [request('r1', 'سارا'), request('r2', 'nima_99')],
    challenges: [challenge('c1', 'مریم')],
  );

  Finder tile(int i) => find.byType(MessageTile).at(i);
  Finder inTile(int i, String text) =>
      find.descendant(of: tile(i), matching: find.text(text));

  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  }

  group('loading, failure, empty', () {
    testWidgets('loading: the mascot card, no spinner', (tester) async {
      repo = sample()..fetchGate = Completer();
      await open(tester);
      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.byType(ZStateCard), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('اعلانی نداری'), findsNothing);
      expect(find.byType(ZGameBackButton), findsOneWidget);
      repo.fetchGate!.complete();
      await _settle(tester);
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.byType(MessageTile), findsNWidgets(3));
    });

    testWidgets('failed first load: Persian message, retry reloads', (
      tester,
    ) async {
      repo = sample()..fetchError = _err(networkErrorCode);
      await open(tester);
      expect(find.text(networkErrorMessage), findsOneWidget);
      expect(find.text('اعلانی نداری'), findsNothing);
      expect(repo.fetches, 1);

      repo.fetchError = null;
      await tester.tap(find.text(ZLoadState.retryLabel));
      await _settle(tester);
      expect(repo.fetches, 2);
      expect(find.byType(MessageTile), findsNWidgets(3));
    });

    testWidgets('a failed refresh keeps the list that was loaded', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      repo.fetchError = _err(networkErrorCode);
      await GetIt.I<MessagesCubit>().refresh();
      await _settle(tester);
      expect(find.byType(MessageTile), findsNWidgets(3));
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('nothing pending: the empty state', (tester) async {
      repo = _Repo();
      await open(tester);
      expect(find.byType(ZEmptyState), findsOneWidget);
      expect(find.text('اعلانی نداری'), findsOneWidget);
      expect(find.byType(MessageTile), findsNothing);
    });

    testWidgets('a signed-out player gets the empty state, not a spinner', (
      tester,
    ) async {
      repo = sample();
      await open(tester, guest: true);
      expect(repo.fetches, 0);
      expect(find.text('اعلانی نداری'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });
  });

  group('pushes held back during a game', () {
    testWidgets('show as a card, count toward the badge, and can be dismissed', (
      tester,
    ) async {
      repo = _Repo();
      await open(tester);
      final cubit = GetIt.I<MessagesCubit>();
      cubit.addMissed('چالش پذیرفته شد', 'وارد بازی شو!');
      await _settle(tester);
      expect(cubit.state.count, 1);
      expect(find.byType(MissedPushTile), findsOneWidget);
      expect(find.text('چالش پذیرفته شد'), findsOneWidget);
      await tester.tap(find.text('باشه'));
      await _settle(tester);
      expect(cubit.state.count, 0);
      expect(find.byType(MissedPushTile), findsNothing);
    });
  });

  group('the list', () {
    testWidgets('header: back button and the canvas title', (tester) async {
      repo = sample();
      await open(tester);
      expect(find.byType(ZGameBackButton), findsOneWidget);
      expect(find.text('اعلان‌ها'), findsOneWidget);
    });

    testWidgets('back pops to where the player came from', (tester) async {
      repo = sample();
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(MessagesScreen), findsNothing);
    });

    testWidgets('requests first, then challenges; Persian copy + initial', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      expect(find.byType(MessageTile), findsNWidgets(3));
      expect(inTile(0, 'درخواست دوستی'), findsOneWidget);
      expect(find.textContaining('سارا'), findsOneWidget);
      expect(inTile(1, 'درخواست دوستی'), findsOneWidget);
      expect(inTile(2, 'دعوت به بازی'), findsOneWidget);
      expect(inTile(2, 'بازی کن'), findsOneWidget);
      expect(inTile(0, 'بپذیر'), findsOneWidget);
      expect(inTile(0, 'رد'), findsOneWidget);
      // The disc shows the sender's initial (upper-cased for Latin names).
      expect(
        find.descendant(of: tile(0), matching: find.text('س')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile(1), matching: find.text('N')),
        findsOneWidget,
      );
      expect(find.byType(ZAccentDisc), findsNWidgets(3));
    });

    testWidgets('only real data: no tabs, read state, times or «بعداً»', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      for (final invented in [
        'خوانده‌نشده',
        'همه خوانده شد',
        'بعداً',
        'پیش',
        'امروز',
        'قبل‌تر',
      ]) {
        expect(find.textContaining(invented), findsNothing, reason: invented);
      }
    });
  });

  group('answering', () {
    testWidgets('accept a request: friends endpoint, tile leaves the list', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      await tester.tap(inTile(0, 'بپذیر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requestAnswers, [('r1', true)]);
      expect(find.byType(MessageTile), findsNWidgets(2));
      expect(find.textContaining('سارا'), findsNothing);
    });

    testWidgets('decline a request sends accept: false', (tester) async {
      repo = sample();
      await open(tester);
      await tester.tap(inTile(1, 'رد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requestAnswers, [('r2', false)]);
      expect(find.byType(MessageTile), findsNWidgets(2));
    });

    testWidgets('accept a challenge enters the room', (tester) async {
      repo = sample();
      await open(tester);
      await tester.tap(inTile(2, 'بازی کن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.challengeAnswers, [('c1', true)]);
      expect(pushed, hasLength(1));
      expect(pushed.single.roomId, 'room-1');
      expect(pushed.single.opponentType, 'multiplayer');
      expect(pushed.single.mode, 'classic');
      expect(pushed.single.opponentName, 'مریم');
    });

    testWidgets('decline a challenge stays on the screen', (tester) async {
      repo = sample();
      await open(tester);
      await tester.tap(inTile(2, 'رد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.challengeAnswers, [('c1', false)]);
      expect(pushed, isEmpty);
      expect(find.byType(MessageTile), findsNWidgets(2));
    });

    testWidgets('while the answer runs: «کمی صبر کن…», no second call', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      repo.respondGate = Completer();
      await tester.tap(inTile(0, 'بپذیر'));
      await tester.pump();
      expect(inTile(0, 'کمی صبر کن…'), findsOneWidget);
      expect(inTile(1, 'بپذیر'), findsOneWidget, reason: 'others unaffected');
      await tester.tap(find.text('کمی صبر کن…'), warnIfMissed: false);
      await tester.tap(inTile(0, 'رد'), warnIfMissed: false);
      repo.respondGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.requestAnswers, [('r1', true)], reason: 'answered once');
    });

    testWidgets('a failed request answer: Persian toast, tile stays', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      repo.respondError = _err(networkErrorCode);
      await tester.tap(inTile(0, 'بپذیر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(networkErrorMessage), findsOneWidget);
      expect(find.byType(MessageTile), findsNWidgets(3));
      expect(inTile(0, 'بپذیر'), findsOneWidget, reason: 'buttons are back');
      await drainToast(tester);
    });

    testWidgets('expired challenge: resync and say it is no longer valid', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      final before = repo.fetches;
      repo.respondError = _err('challenge_not_found');
      repo.challenges = const [];
      await tester.tap(inTile(2, 'بازی کن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.fetches, before + 1);
      expect(find.text(errorMessageFor('challenge_expired')), findsOneWidget);
      expect(find.byType(MessageTile), findsNWidgets(2));
      expect(pushed, isEmpty);
      await drainToast(tester);
    });

    testWidgets('challenger cannot afford: its own Persian text', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      repo.respondError = _err('challenger_cannot_afford');
      await tester.tap(inTile(2, 'بازی کن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(errorMessageFor('challenger_cannot_afford')),
        findsOneWidget,
      );
      await drainToast(tester);
    });

    testWidgets('not enough coins: the shared dialog, invite stays', (
      tester,
    ) async {
      repo = sample();
      await open(tester);
      repo.respondError = _err('insufficient_coins');
      final before = repo.fetches;
      await tester.tap(inTile(2, 'بازی کن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pushed, isEmpty);
      expect(repo.fetches, before, reason: 'no resync: the invite is valid');
      expect(find.byType(MessageTile), findsNWidgets(3));
      expect(find.byType(ZDialogCard), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('buttons name whose invitation they answer', (tester) async {
      final handle = tester.ensureSemantics();
      repo = sample();
      await open(tester);
      expect(
        find.bySemanticsLabel('پذیرفتن درخواست دوستی \u2068سارا\u2069'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('رد درخواست دوستی \u2068سارا\u2069'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('پذیرفتن چالش \u2068مریم\u2069'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the title is a header', (tester) async {
      final handle = tester.ensureSemantics();
      repo = sample();
      await open(tester);
      expect(
        tester.getSemantics(find.text('اعلان‌ها')).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('contrast', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final z = theme.extension<ZColors>()!;
      final name = theme == AppTheme.light ? 'light' : 'dark';
      test('disc glyphs, buttons and text are readable ($name)', () {
        for (final (fill, on) in [
          (z.indigo, z.onIndigo),
          (z.coral, z.onCoral),
        ]) {
          expect(contrastRatio(fill, on), greaterThanOrEqualTo(3));
        }
        // The shared teal button (14dp w900 label) is the canvas's own pair:
        // 3.15:1 in light, so only the large-text floor holds (flagged in
        // REDESIGN_PLAN.md § ZNotifs).
        expect(contrastRatio(z.teal, z.onTeal), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.surface, z.ink), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.surface, z.ink60), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('message_format', () {
    test('a Latin name sits in a bidi isolate', () {
      final face = requestFace(request('x', 'nima_99'));
      expect(face.body, contains('\u2068nima_99\u2069'));
    });

    test('an empty name falls back to the placeholder initial', () {
      expect(challengeFace(challenge('x', '')).glyph, '؟');
    });
  });

  group('layout', () {
    const sizes = [Size(320, 568), Size(360, 640), Size(393, 852)];
    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 1.3, 2.0]) {
          testWidgets(
            'every state: no overflow ${size.width.toInt()}×${size.height.toInt()} ${brightness.name} ×$scale',
            (tester) async {
              final states = <String, _Repo>{
                'list': sample(),
                'long names': _Repo(
                  requests: [
                    request('a', 'a_very_long_latin_username_32chars_xx'),
                  ],
                  challenges: [
                    challenge('b', 'یک_نام_کاربری_خیلی_خیلی_طولانی_فارسی'),
                  ],
                ),
                'empty': _Repo(),
                'error': _Repo()..fetchError = _err(networkErrorCode),
                'loading': _Repo()..fetchGate = Completer(),
              };
              for (final entry in states.entries) {
                await GetIt.I.reset();
                await open(
                  tester,
                  withRepo: entry.value,
                  brightness: brightness,
                  textScale: scale,
                  w: size.width,
                  h: size.height,
                );
                final reason =
                    '${entry.key} ${size.width}×${size.height} ×$scale';
                expect(tester.takeException(), isNull, reason: reason);
                final scroll = find.byType(Scrollable);
                if (scroll.evaluate().isNotEmpty) {
                  await tester.drag(scroll.first, const Offset(0, -3000));
                  await tester.pump();
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: '$reason scrolled',
                  );
                }
              }
            },
          );
        }
      }
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) => expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );

    for (final brightness in Brightness.values) {
      testWidgets('list ${brightness.name}', (tester) async {
        await open(tester, withRepo: sample(), brightness: brightness);
        await shot(tester, 'messages_list_${brightness.name}');
      });
    }

    testWidgets('list small phone dark', (tester) async {
      await open(
        tester,
        withRepo: sample(),
        brightness: Brightness.dark,
        w: 320,
        h: 568,
      );
      await shot(tester, 'messages_list_320_dark');
    });

    testWidgets('empty light', (tester) async {
      await open(tester, withRepo: _Repo());
      await shot(tester, 'messages_empty_light');
    });

    testWidgets('loading dark', (tester) async {
      await open(
        tester,
        withRepo: _Repo()..fetchGate = Completer(),
        brightness: Brightness.dark,
      );
      await shot(tester, 'messages_loading_dark');
    });

    testWidgets('error light', (tester) async {
      await open(
        tester,
        withRepo: _Repo()..fetchError = _err(networkErrorCode),
      );
      await shot(tester, 'messages_error_light');
    });
  });
}
