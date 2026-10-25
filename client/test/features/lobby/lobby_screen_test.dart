import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_hud_coin_pill.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/game/view/widgets/z_game_hud.dart';
import 'package:wordchain/features/game/view/widgets/z_game_shared.dart';
import 'package:wordchain/features/lobby/data/lobby_repository.dart';
import 'package:wordchain/features/lobby/view/lobby_screen.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _signedIn = AuthAuthenticated(
  userId: 'me-1',
  username: 'آرش',
  coins: 1240,
);

const _maryam = FriendModel(
  userId: 'f1',
  username: 'مریم ک.',
  weeklyScore: 1840,
);
const _hossein = FriendModel(userId: 'f2', username: 'حسین ط.', weeklyScore: 0);
const _friends = [_maryam, _hossein];

class _Auth extends FakeAuthCubit {
  _Auth(super.state);

  @override
  bool get isGuest => current is! AuthAuthenticated;
}

class _FakeQueue extends Fake implements LobbyRepository {
  final joins = <String>[];
  Completer<MatchQueueResult>? pending;
  Object? failWith;
  int cancels = 0;

  @override
  Future<MatchQueueResult> joinQueue(String mode) {
    joins.add(mode);
    if (failWith != null) return Future.error(failWith!);
    return (pending = Completer<MatchQueueResult>()).future;
  }

  @override
  Future<void> cancelQueue() async => cancels++;
}

class _FakeSync extends Fake implements SyncService {
  @override
  Future<void> sync() async {}
}

class _FakeNotifications extends Fake implements NotificationService {
  @override
  Stream<String?> get payloadStream => const Stream.empty();
}

class _FakeAds extends Fake implements AdService {
  @override
  bool get rewardedEnabled => false;
}

class _FakeFriends extends Fake implements FriendsRepository {
  List<FriendModel> list = _friends;
  Completer<List<FriendModel>>? gate;
  Object? fetchError;
  Object? sendError;
  int fetches = 0;
  final sent = <(String, String)>[];

  @override
  Future<List<FriendModel>> fetchFriends() async {
    fetches++;
    if (gate != null) return gate!.future;
    if (fetchError != null) throw fetchError!;
    return list;
  }

  @override
  Future<String?> sendChallenge(String friendId, String mode) async {
    sent.add((friendId, mode));
    if (sendError != null) throw sendError!;
    return 'challenge-1';
  }
}

class _FakeProfile extends Fake implements ProfileRepository {
  bool fails = false;

  @override
  Future<ProfileStats> fetchStats() async {
    if (fails) throw const ProfileException('x');
    return const ProfileStats(
      totalMatches: 3,
      wins: 1,
      bestScore: 400,
      bestMatchStreak: 2,
      dailyStreak: 0,
      longestDailyStreak: 0,
      coins: 0,
      level: 5,
    );
  }

  @override
  Future<PremiumPerks> fetchPerks() async => PremiumPerks.none;
}

class _Harness {
  final queue = _FakeQueue();
  final friends = _FakeFriends();
  final profile = _FakeProfile();
  final routes = <String>[];
  Object? gameExtra;

  void register({AuthState auth = _signedIn}) {
    final g = GetIt.I;
    g.registerSingleton<AuthCubit>(_Auth(auth));
    g.registerSingleton<LobbyRepository>(queue);
    g.registerSingleton<SyncService>(_FakeSync());
    g.registerSingleton<NotificationService>(_FakeNotifications());
    g.registerSingleton<FriendsRepository>(friends);
    g.registerSingleton<ProfileRepository>(profile);
    g.registerSingleton<AdService>(_FakeAds());
  }

  Widget app({
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
  }) {
    final router = GoRouter(
      initialLocation: '/lobby',
      routes: [
        GoRoute(path: '/lobby', builder: (_, _) => const LobbyScreen()),
        GoRoute(
          path: '/game',
          builder: (_, state) {
            routes.add('/game');
            gameExtra = state.extra;
            return const Scaffold(body: Text('game'));
          },
        ),
        for (final path in ['/home', '/friends', '/login'])
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

/// Lets the async loads, the dialog entrance and one toast frame run.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Unmounts the screen so the queue's elapsed timer is cancelled.
Future<void> _leave(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

void main() {
  setUpAll(loadVazirmatn);

  late _Harness h;

  setUp(() {
    GetIt.I.reset();
    h = _Harness();
  });

  tearDown(() => GetIt.I.reset());

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
    h.register(auth: auth);
    await tester.pumpWidget(
      h.app(
        brightness: brightness,
        reduceMotion: reduceMotion,
        textScale: textScale,
      ),
    );
    await _settle(tester);
  }

  group('idle', () {
    testWidgets('shows the canvas pieces with real data', (tester) async {
      await open(tester);

      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.text('رویارویی آنلاین'), findsOneWidget);
      expect(find.byType(ZGameBackButton), findsOneWidget);
      expect(find.byType(ZBackButton), findsNothing, reason: 'legacy 34px');

      final pill = tester.widget<ZHudCoinPill>(find.byType(ZHudCoinPill));
      expect(pill.coins, 1240);
      expect(pill.onTap, isNull, reason: 'read-out only, no «+»');

      // Me: indigo disc with the initial, name and the real level.
      expect(find.text('آرش'), findsOneWidget);
      expect(find.text('سطح ۵'), findsOneWidget);
      final me = tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar).first);
      expect(me.letter, 'آ');

      expect(find.text('آمادهٔ شروع؟'), findsOneWidget);
      expect(find.text('در برابر'), findsOneWidget);
      final mascot = tester.widget<ZMascot>(find.byType(ZMascot));
      expect(mascot.mood, ZMascotMood.idle);

      // The real terms: fee 20, pot 40 (GameConstants), AI fallback 30 s.
      expect(find.text('ورودی'), findsOneWidget);
      expect(find.text('۲۰ سکه'), findsOneWidget);
      expect(find.text('جایزهٔ برنده'), findsOneWidget);
      expect(find.text('۴۰ سکه'), findsOneWidget);
      expect(
        find.textContaining('تا ${'۳۰'} ثانیه حریفی پیدا نشود'),
        findsOneWidget,
      );
      expect(GameConstants.matchmakingAiFallbackSec, 30);

      expect(find.text('پیدا کردن حریف'), findsOneWidget);
    });

    testWidgets('omits what nothing backs', (tester) async {
      await open(tester);

      expect(find.textContaining('نفر آنلاین'), findsNothing);
      expect(find.textContaining('هم‌سطح'), findsNothing);
      expect(find.textContaining('مدت هر نوبت'), findsNothing);
      expect(find.textContaining('بدون شرط'), findsNothing);
      expect(find.textContaining('کد اتاق'), findsNothing);
      expect(find.textContaining('برد'), findsNothing);
      expect(find.text('در صف · ۰۰:۰۰'), findsNothing);
    });

    testWidgets('level line stays out when the stats call fails', (
      tester,
    ) async {
      h.profile.fails = true;
      await open(tester);

      expect(find.text('آرش'), findsOneWidget);
      expect(find.textContaining('سطح'), findsNothing);
    });

    testWidgets('back goes home when there is nothing to pop', (tester) async {
      await open(tester);
      await tester.tap(find.byType(ZGameBackButton));
      await _settle(tester);

      expect(h.routes, contains('/home'));
    });

    testWidgets('reduced motion: nothing keeps scheduling frames', (
      tester,
    ) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('queue', () {
    testWidgets('search → elapsed time → cancel', (tester) async {
      await open(tester);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);

      expect(h.queue.joins, ['classic']);
      expect(find.text('در جست‌وجو…'), findsOneWidget);
      expect(find.text('در صف · ۰۰:۰۰'), findsOneWidget);
      expect(find.text('لغو جست‌وجو'), findsOneWidget);
      expect(find.text('پیدا کردن حریف'), findsNothing);
      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.thinking,
      );

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('در صف · ۰۰:۰۳'), findsOneWidget);

      await tester.tap(find.text('لغو جست‌وجو'));
      await _settle(tester);

      expect(h.queue.cancels, 1);
      expect(find.text('پیدا کردن حریف'), findsOneWidget);
      expect(find.text('در جست‌وجو…'), findsNothing);
      await _leave(tester);
    });

    testWidgets('radar rings only run while searching and animating', (
      tester,
    ) async {
      await open(tester, reduceMotion: false);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.binding.hasScheduledFrame, isTrue);
      await _leave(tester);
    });

    testWidgets('a match navigates to the game with the room', (tester) async {
      await open(tester);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);

      h.queue.pending!.complete(
        const MatchQueueResult(roomId: 'room-9', isAi: false),
      );
      await _settle(tester);

      expect(h.routes, ['/game']);
      final args = h.gameExtra as GameRouteArgs;
      expect(args.roomId, 'room-9');
      expect(args.opponentType, 'multiplayer');
      expect(args.mode, 'classic');
      expect(args.myPlayerId, 'me-1');
    });

    testWidgets('402 insufficient coins opens the earn-coins dialog', (
      tester,
    ) async {
      h.queue.failWith = const LobbyException(
        'سکهٔ کافی نداری',
        code: 'insufficient_coins',
      );
      await open(tester);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);

      expect(find.text('متوجه شدم'), findsOneWidget);
      expect(
        find.textContaining('برای این کار ${'۲۰'} سکه لازم است'),
        findsOneWidget,
      );
      // Back to idle underneath: no retry block, the normal button.
      expect(find.text('پیدا کردن حریف'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsNothing);
    });

    testWidgets('other failures show the reason and a retry', (tester) async {
      h.queue.failWith = const LobbyException(
        'حریفی پیدا نشد. دوباره تلاش کن.',
      );
      await open(tester);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);

      expect(find.text('حریفی پیدا نشد. دوباره تلاش کن.'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      expect(find.text('حریف پیدا نشد'), findsOneWidget);
      expect(
        tester.widget<ZMascot>(find.byType(ZMascot)).mood,
        ZMascotMood.sad,
      );

      h.queue.failWith = null;
      await tester.tap(find.text('تلاش دوباره'));
      await _settle(tester);

      expect(h.queue.joins, ['classic', 'classic']);
      expect(find.text('لغو جست‌وجو'), findsOneWidget);
      await _leave(tester);
    });
  });

  group('guest', () {
    testWidgets('no balance, no friends call, the button sends to login', (
      tester,
    ) async {
      await open(tester, auth: const AuthGuest());

      expect(find.byType(ZHudCoinPill), findsNothing);
      expect(h.friends.fetches, 0);
      expect(
        find.textContaining('برای دعوت دوستانت اول وارد حسابت شو'),
        findsOneWidget,
      );
      expect(find.text('تو'), findsOneWidget);

      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);

      expect(h.queue.joins, isEmpty);
      expect(h.routes, ['/login?return=/lobby']);
    });

    testWidgets('the friends notice also leads to login', (tester) async {
      await open(tester, auth: const AuthGuest());
      await tester.ensureVisible(find.text('ورود'));
      await tester.pump();
      await tester.tap(find.text('ورود'));
      await _settle(tester);

      expect(h.routes, ['/login?return=/lobby']);
    });
  });

  group('friends', () {
    testWidgets('real rows: name, weekly score, count', (tester) async {
      await open(tester);

      expect(find.text('بازی با دوستان'), findsOneWidget);
      expect(find.text('۲ نفر'), findsOneWidget);
      expect(find.text('مریم ک.'), findsOneWidget);
      expect(find.text('حسین ط.'), findsOneWidget);
      expect(find.text('۱٬۸۴۰ امتیاز این هفته'), findsOneWidget);
      expect(find.text('۰ امتیاز این هفته'), findsOneWidget);
      expect(find.text('دعوت به بازی'), findsNWidgets(2));
    });

    testWidgets('loading shows skeleton rows, no names', (tester) async {
      h.friends.gate = Completer();
      await open(tester);

      expect(find.text('بازی با دوستان'), findsOneWidget);
      expect(find.text('۲ نفر'), findsNothing);
      expect(find.text('دعوت به بازی'), findsNothing);

      h.friends.gate!.complete(_friends);
      await _settle(tester);
      expect(find.text('مریم ک.'), findsOneWidget);
    });

    testWidgets('empty: says so and leads to the friends tab', (tester) async {
      h.friends.list = const [];
      await open(tester);

      expect(find.textContaining('هنوز دوستی اضافه نکرده‌ای'), findsOneWidget);
      expect(find.text('۰ نفر'), findsNothing);

      await tester.tap(find.text('افزودن دوست'));
      await _settle(tester);
      expect(h.routes, ['/friends']);
    });

    testWidgets('error: Persian message and a working retry', (tester) async {
      h.friends.fetchError = const FriendsException(
        code: 'network_error',
        message: 'خطا در اتصال به اینترنت',
      );
      await open(tester);

      expect(find.text('خطا در اتصال به اینترنت'), findsOneWidget);

      h.friends.fetchError = null;
      await tester.tap(find.text('تلاش دوباره'));
      await _settle(tester);

      expect(h.friends.fetches, 2);
      expect(find.text('مریم ک.'), findsOneWidget);
    });

    testWidgets('invite sends a Classic challenge once, then reads «دعوت شد»', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);

      expect(h.friends.sent, [('f1', 'classic')]);
      expect(find.textContaining('دعوت‌نامه برای'), findsOneWidget);
      expect(find.textContaining('مریم ک.'), findsWidgets);
      expect(find.text('دعوت شد'), findsOneWidget);
      expect(find.text('دعوت به بازی'), findsOneWidget);

      // The sent button is inert: no second challenge.
      await tester.tap(find.text('دعوت شد'));
      await _settle(tester);
      expect(h.friends.sent, hasLength(1));
    });

    testWidgets('a failed invite toasts the server message and stays open', (
      tester,
    ) async {
      h.friends.sendError = const FriendsException(
        code: 'not_friends',
        message: 'شما دوست نیستید',
      );
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);

      expect(find.text('شما دوست نیستید'), findsOneWidget);
      expect(find.text('دعوت به بازی'), findsNWidgets(2));
      expect(find.text('دعوت شد'), findsNothing);
    });

    testWidgets('an invite you cannot afford opens the coins dialog', (
      tester,
    ) async {
      h.friends.sendError = const FriendsException(
        code: 'insufficient_coins',
        message: 'سکهٔ کافی نداری',
      );
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);

      expect(find.text('متوجه شدم'), findsOneWidget);
      expect(find.text('دعوت شد'), findsNothing);
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
        final tag =
            '${size.width.toInt()}×${size.height.toInt()} ${brightness.name}';

        testWidgets('idle, 6 friends, long names: no overflow $tag', (
          tester,
        ) async {
          h.friends.list = [
            for (var i = 0; i < 6; i++)
              FriendModel(
                userId: 'f$i',
                username:
                    i == 1 ? 'یک_نام_کاربری_خیلی_خیلی_بلند_فارسی' : 'دوست $i',
                weeklyScore: 1000000 + i,
              ),
          ];
          await open(
            tester,
            auth: const AuthAuthenticated(
              userId: 'me-1',
              username: 'نام_کاربری_بسیار_بلند_برای_تست',
              coins: 123456789,
            ),
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          expect(tester.takeException(), isNull);
          // The primary button is on screen without scrolling.
          final cta = tester.getRect(find.text('پیدا کردن حریف'));
          expect(cta.bottom, lessThan(size.height), reason: 'CTA below fold');
        });

        testWidgets('searching: no overflow $tag', (tester) async {
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
            reduceMotion: false,
          );
          await tester.tap(find.text('پیدا کردن حریف'));
          await _settle(tester);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _leave(tester);
        });

        testWidgets('error + guest + loading: no overflow $tag', (
          tester,
        ) async {
          h.queue.failWith = const LobbyException('پیوستن به صف ناموفق بود');
          h.friends.gate = Completer();
          await open(
            tester,
            brightness: brightness,
            w: size.width,
            hgt: size.height,
          );
          await tester.tap(find.text('پیدا کردن حریف'));
          await _settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('text ×$scale: no overflow, fixed controls capped at 1.3', (
        tester,
      ) async {
        await open(tester, textScale: scale, w: 320, hgt: 568);
        expect(tester.takeException(), isNull);
        // The friends card starts below the fold on this phone.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pump();
        expect(tester.takeException(), isNull);

        for (final label in [
          'پیدا کردن حریف',
          'دعوت به بازی',
          'رویارویی آنلاین',
        ]) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label).first,
          );
          expect(
            paragraph.textScaler.scale(10),
            lessThanOrEqualTo(13.01),
            reason: label,
          );
        }
      });
    }

    testWidgets('searching at text ×2.0 on a 320 wide phone', (tester) async {
      await open(tester, textScale: 2.0, w: 320, hgt: 568);
      // At 2× the footnote grows and the button sits below the fold.
      await tester.ensureVisible(find.text('پیدا کردن حریف'));
      await tester.pump();
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });
  });

  group('colours', () {
    for (final brightness in Brightness.values) {
      testWidgets('text on its fill is readable (${brightness.name})', (
        tester,
      ) async {
        await open(tester, brightness: brightness);
        final z = tester.element(find.byType(LobbyScreen)).z;

        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.onCoral, z.coral), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(4.5));
        // Footnote and the «دعوت شد» label.
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(z.onInkSurface, z.inkSurface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    for (final brightness in Brightness.values) {
      final b = brightness.name;

      testWidgets('idle $b', (tester) async {
        await open(tester, brightness: brightness, reduceMotion: true);
        await shot(tester, 'z_lobby_idle_$b');
      });

      testWidgets('searching $b', (tester) async {
        await open(tester, brightness: brightness, reduceMotion: false);
        await tester.tap(find.text('پیدا کردن حریف'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 1500));
        await shot(tester, 'z_lobby_searching_$b');
        await _leave(tester);
      });
    }

    testWidgets('error light', (tester) async {
      h.queue.failWith = const LobbyException(
        'حریفی پیدا نشد. دوباره تلاش کن.',
      );
      await open(tester);
      await tester.tap(find.text('پیدا کردن حریف'));
      await _settle(tester);
      await shot(tester, 'z_lobby_error_light');
    });

    testWidgets('invited + small phone dark', (tester) async {
      await open(tester, brightness: Brightness.dark, w: 320, hgt: 568);
      await tester.ensureVisible(find.text('دعوت به بازی').first);
      await tester.pump();
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await shot(tester, 'z_lobby_invited_320_dark');
    });

    testWidgets('empty friends + guest light', (tester) async {
      await open(tester, auth: const AuthGuest());
      await shot(tester, 'z_lobby_guest_light');
    });
  });
}
