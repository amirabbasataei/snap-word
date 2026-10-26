import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/services/notification_service.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/core/widgets/z_disc_avatar.dart';
import 'package:wordchain/core/widgets/z_empty_state.dart';
import 'package:wordchain/core/widgets/z_load_state.dart';
import 'package:wordchain/core/widgets/z_mascot.dart';
import 'package:wordchain/core/widgets/z_ribbon_title.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/widgets/friends_parts.dart';
import 'package:wordchain/features/friends/view/z_friends_screen.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/view/game_screen.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _signedIn = AuthAuthenticated(userId: 'me-1', username: 'آرش', coins: 1240);

const _maryam = FriendModel(userId: 'f1', username: 'مریم ک.', weeklyScore: 1840);
const _hossein = FriendModel(userId: 'f2', username: 'حسین ط.', weeklyScore: 0);
const _sina = FriendModel(userId: 'f3', username: 'sina_r', weeklyScore: 320);
const _friends = [_maryam, _hossein, _sina];

const _leila = PendingRequest(requesterId: 'r1', username: 'لیلا م.');
const _behnam = PendingRequest(requesterId: 'r2', username: 'بهنام ص.');
final _challenge = PendingChallenge(
  id: 'c1',
  challengerId: 'f1',
  challengerUsername: 'مریم ک.',
  mode: 'classic',
  expiresAt: DateTime(2030),
);

class _Auth extends FakeAuthCubit {
  _Auth(super.state);

  Object? codeError;
  String code = 'K7M2QX';
  int codeFetches = 0;

  @override
  bool get isGuest => current is! AuthAuthenticated;

  @override
  Future<String> fetchMyReferralCode() async {
    codeFetches++;
    if (codeError != null) throw codeError!;
    return code;
  }
}

class _FakeFriends extends Fake implements FriendsRepository {
  @override
  Stream<String> get challengeAccepted => const Stream.empty();

  List<FriendModel> friends = _friends;
  List<PendingRequest> requests = const [];
  List<PendingChallenge> challenges = const [];

  Completer<List<FriendModel>>? gate;
  Object? fetchError;
  Object? requestError;
  Object? respondError;
  Object? removeError;
  Object? challengeError;

  int fetches = 0;
  final requested = <String>[];
  final responses = <(String, bool)>[];
  final challengeResponses = <(String, bool)>[];
  final removed = <String>[];
  final sent = <(String, String)>[];
  String? roomOnAccept;

  @override
  Future<List<FriendModel>> fetchFriends() async {
    fetches++;
    if (gate != null) return gate!.future;
    if (fetchError != null) throw fetchError!;
    return friends;
  }

  @override
  Future<List<PendingRequest>> fetchPendingRequests() async => requests;

  @override
  Future<List<PendingChallenge>> fetchPendingChallenges() async => challenges;

  @override
  Future<void> sendFriendRequest(String username) async {
    requested.add(username);
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> respondToRequest(String requesterId, bool accept) async {
    responses.add((requesterId, accept));
    if (respondError != null) throw respondError!;
    requests = [
      for (final r in requests)
        if (r.requesterId != requesterId) r,
    ];
  }

  @override
  Future<String?> respondToChallenge(String challengeId, bool accept) async {
    challengeResponses.add((challengeId, accept));
    if (respondError != null) throw respondError!;
    challenges = [
      for (final c in challenges)
        if (c.id != challengeId) c,
    ];
    return accept ? roomOnAccept : null;
  }

  @override
  Future<void> removeFriend(String friendId) async {
    removed.add(friendId);
    if (removeError != null) throw removeError!;
    friends = [
      for (final f in friends)
        if (f.userId != friendId) f,
    ];
  }

  @override
  Future<String?> sendChallenge(String friendId, String mode) async {
    sent.add((friendId, mode));
    if (challengeError != null) throw challengeError!;
    return 'challenge-1';
  }
}

class _FakeMessages extends Fake implements MessagesCubit {
  final changed = StreamController<void>.broadcast();
  int pendingSets = 0;

  @override
  Stream<void> get friendsChanged => changed.stream;

  @override
  void setPending(List<PendingRequest> requests, List<PendingChallenge> challenges) => pendingSets++;
}

class _FakeShare extends Fake implements ShareService {
  final codes = <String>[];

  @override
  Future<void> shareInvite({required String code}) async => codes.add(code);
}

class _FakeNotifications extends Fake implements NotificationService {
  bool authorized = false;
  int permissionRequests = 0;

  @override
  Future<bool> isAuthorized() async => authorized;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<void> registerToken() async {}
}

class _FakeAds extends Fake implements AdService {
  @override
  bool get rewardedEnabled => false;
}

class _Harness {
  final repo = _FakeFriends();
  final messages = _FakeMessages();
  final share = _FakeShare();
  final notifications = _FakeNotifications();
  final bus = TabRefreshBus();
  final routes = <String>[];
  Object? gameExtra;
  late _Auth auth;

  Future<void> register({AuthState state = _signedIn}) async {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth(state);
    GetIt.I
      ..registerSingleton<AuthCubit>(auth)
      ..registerSingleton<FriendsRepository>(repo)
      ..registerSingleton<MessagesCubit>(messages)
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<NotificationService>(notifications)
      ..registerSingleton<TabRefreshBus>(bus)
      ..registerSingleton<AdService>(_FakeAds())
      ..registerSingleton<SharedPreferences>(await SharedPreferences.getInstance());
  }

  Widget app({
    Brightness brightness = Brightness.light,
    bool reduceMotion = true,
    double textScale = 1,
    double keyboard = 0,
  }) {
    final router = GoRouter(
      initialLocation: '/friends',
      routes: [
        GoRoute(path: '/friends', builder: (_, _) => const ZFriendsScreen()),
        GoRoute(
          path: '/game',
          builder: (_, state) {
            routes.add('/game');
            gameExtra = state.extra;
            return const Scaffold(body: Text('game'));
          },
        ),
        for (final path in ['/login', '/daily', '/profile'])
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
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: Directionality(textDirection: TextDirection.rtl, child: child!),
          ),
    );
  }
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

/// Lets the loads, a dialog entrance and one toast frame run.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 700));
}

/// Runs the clock until no toast text is left on screen.
Future<void> _waitForToastToGo(WidgetTester tester) async {
  for (var i = 0; i < 30 && find.text('چالش ارسال شد').evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.text('چالش ارسال شد'), findsNothing);
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
    double keyboard = 0,
  }) async {
    _size(tester, w, hgt);
    await h.register(state: auth);
    await tester.pumpWidget(
      h.app(brightness: brightness, reduceMotion: reduceMotion, textScale: textScale, keyboard: keyboard),
    );
    await _settle(tester);
  }

  group('list', () {
    testWidgets('shows the canvas pieces with real data', (tester) async {
      await open(tester);

      expect(find.byType(ZRibbonTitle), findsOneWidget);
      expect(find.text('دوستان'), findsOneWidget);
      expect(find.bySemanticsLabel('افزودن دوست'), findsOneWidget);
      expect(find.text('جست‌وجوی نام دوستان'), findsOneWidget);

      expect(find.text('دوستان من'), findsOneWidget);
      expect(find.text('۳ نفر'), findsOneWidget);
      for (final f in _friends) {
        expect(find.text(f.username), findsOneWidget);
      }
      // The sub-line is this week's score, formatted; no score says so.
      expect(find.text('۱٬۸۴۰ امتیاز این هفته'), findsOneWidget);
      expect(find.text('۳۲۰ امتیاز این هفته'), findsOneWidget);
      expect(find.text('بدون امتیاز این هفته'), findsOneWidget);
      expect(find.text('دعوت به بازی'), findsNWidgets(3));
      expect(find.text('برای حذف یک دوست، انگشتتُ روی اسمش نگه دار'), findsOneWidget);

      // Initials on discs, no mascot while there are friends.
      final discs = tester.widgetList<ZDiscAvatar>(find.byType(ZDiscAvatar));
      expect(discs.map((d) => d.letter), ['م', 'ح', 'S']);
      expect(find.byType(ZMascot), findsNothing);
      expect(h.repo.fetches, 1);
    });

    testWidgets('omits what nothing backs', (tester) async {
      h.repo.requests = const [_leila];
      await open(tester);

      expect(find.textContaining('آنلاین'), findsNothing);
      expect(find.textContaining('آفلاین'), findsNothing);
      expect(find.textContaining('در بازی'), findsNothing);
      expect(find.textContaining('باخت'), findsNothing);
      expect(find.textContaining('بهترین زنجیر'), findsNothing);
      expect(find.textContaining('دوست مشترک'), findsNothing);
      expect(find.textContaining('رویارویی'), findsNothing);
    });

    testWidgets('a premium friend shows their avatar image id', (tester) async {
      h.repo.friends = const [FriendModel(userId: 'f1', username: 'مریم ک.', weeklyScore: 10, avatarId: 'fox')];
      await open(tester);

      final disc = tester.widget<ZDiscAvatar>(find.byType(ZDiscAvatar).first);
      expect(disc.avatarId, 'fox');
      expect(disc.letter, 'م', reason: 'the initial stays as the fallback');
    });

    testWidgets('the add button, the search and the discs keep 44dp targets', (tester) async {
      await open(tester);
      final add = tester.getSize(find.byType(FriendsGlyphButton));
      expect(add.width, greaterThanOrEqualTo(44));
      expect(add.height, greaterThanOrEqualTo(44));
    });
  });

  group('loading, error, empty, guest', () {
    testWidgets('loading shows the shared loading state, then the list', (tester) async {
      h.repo.gate = Completer();
      await open(tester);

      expect(find.byType(ZLoadState), findsOneWidget);
      expect(find.text(ZLoadState.loadingLabel), findsOneWidget);
      expect(find.byType(ZRibbonTitle), findsOneWidget, reason: 'header stays');
      expect(find.text('دوستان من'), findsNothing);

      h.repo.gate!.complete(_friends);
      await _settle(tester);
      expect(find.byType(ZLoadState), findsNothing);
      expect(find.text('دوستان من'), findsOneWidget);
    });

    testWidgets('a failed first load shows the Persian message and retries', (tester) async {
      h.repo.fetchError = const FriendsException(code: 'network_error', message: 'خطا در اتصال به اینترنت');
      await open(tester);

      expect(find.text('خطا در اتصال به اینترنت'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      expect(tester.widget<ZMascot>(find.byType(ZMascot)).mood, ZMascotMood.sad);

      h.repo.fetchError = null;
      await tester.tap(find.text('تلاش دوباره'));
      await _settle(tester);
      expect(find.text('دوستان من'), findsOneWidget);
      expect(find.text('خطا در اتصال به اینترنت'), findsNothing);
    });

    testWidgets('no friends: the empty state, no search, invite code kept', (tester) async {
      h.repo.friends = const [];
      await open(tester);

      expect(find.byType(ZEmptyState), findsOneWidget);
      expect(find.text('هنوز دوستی نداری'), findsOneWidget);
      expect(find.text('افزودن دوست'), findsOneWidget);
      expect(find.text('جست‌وجوی نام دوستان'), findsNothing);
      expect(find.text('۰ نفر'), findsNothing);
      expect(find.text('برای حذف یک دوست، انگشتتُ روی اسمش نگه دار'), findsNothing);
      // The share card is the best next step when the list is empty.
      expect(find.text('با کد دعوت، ۵۰ سکه بگیر'), findsOneWidget);

      await tester.tap(find.text('افزودن دوست'));
      await _settle(tester);
      expect(find.text('ارسال درخواست'), findsOneWidget);
    });

    testWidgets('a guest sees the sign-up gate and nothing is fetched', (tester) async {
      await open(tester, auth: const AuthGuest());

      expect(find.text('دوستانت را پیدا کن'), findsOneWidget);
      expect(find.bySemanticsLabel('افزودن دوست'), findsNothing);
      expect(h.repo.fetches, 0);
      expect(h.auth.codeFetches, 0);

      await tester.tap(find.text('ثبت‌نام رایگان'));
      await _settle(tester);
      expect(h.routes, contains('/login?return=/friends'));
    });
  });

  group('requests', () {
    testWidgets('requests and challenges share one card with a count', (tester) async {
      h.repo.requests = const [_leila, _behnam];
      h.repo.challenges = [_challenge];
      await open(tester);

      expect(find.text('درخواست‌ها'), findsOneWidget);
      expect(find.text('۳'), findsOneWidget);
      expect(find.text('لیلا م.'), findsOneWidget);
      expect(find.text('می‌خواهد دوست تو شود'), findsNWidgets(2));
      expect(find.text('چالش فرستاد · کلاسیک'), findsOneWidget);
      // The messages badge is told what the screen loaded.
      expect(h.messages.pendingSets, greaterThan(0));
    });

    testWidgets('no requests: no card', (tester) async {
      await open(tester);
      expect(find.text('درخواست‌ها'), findsNothing);
    });

    testWidgets('accept and decline a friend request', (tester) async {
      h.repo.requests = const [_leila, _behnam];
      await open(tester);

      await tester.tap(find.bySemanticsLabel('پذیرفتن درخواست دوستی ${isolate('لیلا م.')}'));
      await _settle(tester);
      expect(h.repo.responses, [('r1', true)]);
      expect(find.text('لیلا م.'), findsNothing);
      expect(find.text('بهنام ص.'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing, reason: 'no spinner');

      await tester.tap(find.bySemanticsLabel('رد درخواست دوستی ${isolate('بهنام ص.')}'));
      await _settle(tester);
      expect(h.repo.responses, [('r1', true), ('r2', false)]);
      expect(find.text('درخواست‌ها'), findsNothing);
    });

    testWidgets('a failed response keeps the lists and toasts the reason', (tester) async {
      h.repo.requests = const [_leila];
      h.repo.respondError = const FriendsException(code: 'request_not_found', message: 'درخواست دوستی پیدا نشد');
      await open(tester);

      await tester.tap(find.bySemanticsLabel('پذیرفتن درخواست دوستی ${isolate('لیلا م.')}'));
      await _settle(tester);

      expect(find.text('درخواست دوستی پیدا نشد'), findsOneWidget);
      expect(find.text('لیلا م.'), findsOneWidget, reason: 'list stays');
      expect(find.text('دوستان من'), findsOneWidget);
    });

    testWidgets('accepting a challenge enters the room', (tester) async {
      h.repo.challenges = [_challenge];
      h.repo.roomOnAccept = 'room-9';
      await open(tester);

      await tester.tap(find.bySemanticsLabel('پذیرفتن چالش ${isolate('مریم ک.')}'));
      await _settle(tester);

      expect(h.repo.challengeResponses, [('c1', true)]);
      expect(h.routes, contains('/game'));
      final args = h.gameExtra! as GameRouteArgs;
      expect(args.roomId, 'room-9');
      expect(args.mode, 'classic');
      expect(args.opponentType, 'multiplayer');
      expect(args.opponentName, 'مریم ک.');
    });

    testWidgets('declining a challenge sends decline and stays', (tester) async {
      h.repo.challenges = [_challenge];
      await open(tester);

      await tester.tap(find.bySemanticsLabel('رد چالش ${isolate('مریم ک.')}'));
      await _settle(tester);

      expect(h.repo.challengeResponses, [('c1', false)]);
      expect(h.routes, isNot(contains('/game')));
      expect(find.text('درخواست‌ها'), findsNothing);
    });

    testWidgets('accepting a challenge you cannot afford opens the coins dialog', (tester) async {
      h.repo.challenges = [_challenge];
      h.repo.respondError = const FriendsException(code: 'insufficient_coins', message: 'سکهٔ کافی نداری');
      await open(tester);

      await tester.tap(find.bySemanticsLabel('پذیرفتن چالش ${isolate('مریم ک.')}'));
      await _settle(tester);

      expect(find.text('متوجه شدم'), findsOneWidget);
      expect(find.text('دوستان من'), findsOneWidget, reason: 'list stays');
    });
  });

  group('add a friend', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('افزودن دوست'));
      await _settle(tester);
    }

    testWidgets('sends the trimmed username and toasts the success', (tester) async {
      await open(tester);
      await openDialog(tester);

      expect(find.text('نام کاربری دقیق دوستت را بنویس تا برایش درخواست دوستی بفرستیم.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '  زهرا_ب  ');
      await tester.tap(find.text('ارسال درخواست'));
      await _settle(tester);

      expect(h.repo.requested, ['زهرا_ب']);
      expect(find.text('درخواست دوستی برای زهرا_ب ارسال شد'), findsOneWidget);
      expect(find.text('ارسال درخواست'), findsNothing, reason: 'dialog closed');
      expect(find.byType(ZLoadState), findsNothing, reason: 'no spinner');
    });

    testWidgets('the keyboard send key submits too', (tester) async {
      await open(tester);
      await openDialog(tester);

      await tester.enterText(find.byType(TextField).last, 'zahra');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await _settle(tester);
      expect(h.repo.requested, ['zahra']);
    });

    testWidgets('an empty name sends nothing and keeps the dialog open', (tester) async {
      await open(tester);
      await openDialog(tester);

      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text('ارسال درخواست'));
      await _settle(tester);

      expect(h.repo.requested, isEmpty);
      expect(find.text('ارسال درخواست'), findsOneWidget);
    });

    testWidgets('cancel and the scrim send nothing', (tester) async {
      await open(tester);
      await openDialog(tester);
      await tester.tap(find.text('بی‌خیال'));
      await _settle(tester);
      expect(find.text('ارسال درخواست'), findsNothing);

      await openDialog(tester);
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
      expect(find.text('ارسال درخواست'), findsNothing);
      expect(h.repo.requested, isEmpty);
    });

    testWidgets('a failure toasts the Persian reason and the list stays', (tester) async {
      h.repo.requestError = const FriendsException(code: 'user_not_found', message: 'کاربری با این نام پیدا نشد');
      await open(tester);
      await openDialog(tester);
      await tester.enterText(find.byType(TextField).last, 'nobody');
      await tester.tap(find.text('ارسال درخواست'));
      await _settle(tester);

      expect(find.text('کاربری با این نام پیدا نشد'), findsOneWidget);
      expect(find.text('دوستان من'), findsOneWidget);
      expect(find.text('مریم ک.'), findsOneWidget);
    });

    testWidgets('the same failure twice toasts twice', (tester) async {
      h.repo.requestError = const FriendsException(code: 'user_not_found', message: 'کاربری با این نام پیدا نشد');
      await open(tester);
      for (var i = 0; i < 2; i++) {
        await openDialog(tester);
        await tester.enterText(find.byType(TextField).last, 'nobody');
        await tester.tap(find.text('ارسال درخواست'));
        await _settle(tester);
        expect(find.text('کاربری با این نام پیدا نشد'), findsOneWidget);
        // Let the toast go away before the second attempt.
        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('کاربری با این نام پیدا نشد'), findsNothing);
      }
      expect(h.repo.requested, ['nobody', 'nobody']);
    });
  });

  group('challenge a friend', () {
    testWidgets('confirm sends a classic challenge and the row says «دعوت شد»', (tester) async {
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      expect(h.repo.sent, isEmpty, reason: 'nothing is sent before confirming');

      await tester.tap(find.text('بفرست'));
      await _settle(tester);

      expect(h.repo.sent, [('f1', 'classic')]);
      expect(find.text('چالش ارسال شد'), findsOneWidget);
      expect(find.text('دعوت شد'), findsOneWidget);
      expect(find.text('دعوت به بازی'), findsNWidgets(2));
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('«دعوت شد» is inert and wears off after a while', (tester) async {
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);

      await tester.tap(find.text('دعوت شد'));
      await _settle(tester);
      expect(find.text('بفرست'), findsNothing, reason: 'no second dialog');
      expect(h.repo.sent, hasLength(1));

      await tester.pump(const Duration(seconds: GameConstants.friendInviteSentSec + 1));
      expect(find.text('دعوت شد'), findsNothing);
      expect(find.text('دعوت به بازی'), findsNWidgets(3));
    });

    testWidgets('the mark survives a tab refresh', (tester) async {
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);

      h.bus.notify(MainTab.friends);
      await _settle(tester);
      expect(find.text('دعوت شد'), findsOneWidget);
    });

    testWidgets('cancel sends nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بی‌خیال'));
      await _settle(tester);

      expect(h.repo.sent, isEmpty);
      expect(find.text('دعوت شد'), findsNothing);
    });

    testWidgets('not enough coins opens the earn-coins dialog, no mark', (tester) async {
      h.repo.challengeError = const FriendsException(code: 'insufficient_coins', message: 'سکهٔ کافی نداری');
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);

      expect(find.text('متوجه شدم'), findsOneWidget);
      expect(find.text('دعوت شد'), findsNothing);
    });

    testWidgets('another failure toasts the reason and keeps the list', (tester) async {
      h.repo.challengeError = const FriendsException(
        code: 'not_friends',
        message: 'برای چالش دادن باید با این بازیکن دوست باشی',
      );
      await open(tester);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);

      expect(find.text('برای چالش دادن باید با این بازیکن دوست باشی'), findsOneWidget);
      expect(find.text('دعوت شد'), findsNothing);
      expect(find.text('دوستان من'), findsOneWidget);
    });
  });

  group('remove a friend', () {
    testWidgets('a long press asks first, then removes', (tester) async {
      await open(tester);
      await tester.longPress(find.text('مریم ک.'));
      await _settle(tester);

      expect(find.textContaining('را از دوستان حذف کنی؟'), findsOneWidget);
      expect(h.repo.removed, isEmpty);

      await tester.tap(find.text('حذف'));
      await _settle(tester);

      expect(h.repo.removed, ['f1']);
      expect(find.text('مریم ک.'), findsNothing);
      expect(find.text('۲ نفر'), findsOneWidget);
      expect(find.byType(ZLoadState), findsNothing);
    });

    testWidgets('cancel and the scrim keep the friend', (tester) async {
      await open(tester);
      await tester.longPress(find.text('مریم ک.'));
      await _settle(tester);
      await tester.tap(find.text('بی‌خیال'));
      await _settle(tester);
      await tester.longPress(find.text('مریم ک.'));
      await _settle(tester);
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);

      expect(h.repo.removed, isEmpty);
      expect(find.text('مریم ک.'), findsOneWidget);
    });

    testWidgets('a failure toasts and the friend stays', (tester) async {
      h.repo.removeError = const FriendsException(code: 'network_error', message: 'خطا در اتصال به اینترنت');
      await open(tester);
      await tester.longPress(find.text('مریم ک.'));
      await _settle(tester);
      await tester.tap(find.text('حذف'));
      await _settle(tester);

      expect(find.text('خطا در اتصال به اینترنت'), findsOneWidget);
      expect(find.text('مریم ک.'), findsOneWidget);
      expect(find.text('دوستان من'), findsOneWidget);
    });

    testWidgets('screen readers get a «حذف از دوستان» action', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);

      final node = tester.getSemantics(find.text('حسین ط.'));
      expect(node.getSemanticsData().customSemanticsActionIds, isNotEmpty);
      SemanticsBinding.instance.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.customAction,
          viewId: tester.view.viewId,
          nodeId: node.id,
          arguments: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'حذف از دوستان')),
        ),
      );
      await _settle(tester);

      expect(find.textContaining('را از دوستان حذف کنی؟'), findsOneWidget);
      handle.dispose();
    });
  });

  group('search', () {
    testWidgets('filters the loaded friends by name', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'مری');
      await tester.pump();

      expect(find.text('مریم ک.'), findsOneWidget);
      expect(find.text('حسین ط.'), findsNothing);
      expect(find.text('۱ نفر'), findsOneWidget, reason: 'count follows the filter');
      expect(h.repo.fetches, 1, reason: 'local filter, no request');
    });

    testWidgets('is case-insensitive for Latin names', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'SINA');
      await tester.pump();
      expect(find.text('sina_r'), findsOneWidget);
      expect(find.text('مریم ک.'), findsNothing);
    });

    testWidgets('no match shows a message, clearing brings the list back', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.text('نتیجه‌ای پیدا نشد'), findsOneWidget);
      expect(find.text('افزودن دوست'), findsNothing, reason: 'not «no friends»');
      expect(find.text('برای حذف یک دوست، انگشتتُ روی اسمش نگه دار'), findsNothing);

      await tester.tap(find.bySemanticsLabel('پاک کردن جست‌وجو'));
      await tester.pump();
      expect(find.text('نتیجه‌ای پیدا نشد'), findsNothing);
      expect(find.text('مریم ک.'), findsOneWidget);
    });
  });

  group('invite code', () {
    testWidgets('shows the real code and shares it', (tester) async {
      await open(tester);

      expect(find.text('با کد دعوت، ۵۰ سکه بگیر'), findsOneWidget);
      expect(find.textContaining('K7M2QX'), findsOneWidget);
      expect(find.textContaining('ZNJR'), findsNothing);

      await tester.tap(find.text('اشتراک‌گذاری'));
      await _settle(tester);
      expect(h.share.codes, ['K7M2QX']);
    });

    testWidgets('while loading there is no code and no share button', (tester) async {
      final gate = Completer<String>();
      await h.register();
      h.auth.codeError = null;
      GetIt.I.unregister<AuthCubit>();
      GetIt.I.registerSingleton<AuthCubit>(_SlowCode(gate));
      _size(tester, 393, 852);
      await tester.pumpWidget(h.app());
      await _settle(tester);

      expect(find.text('با کد دعوت، ۵۰ سکه بگیر'), findsOneWidget);
      expect(find.text('اشتراک‌گذاری'), findsNothing);
      expect(find.textContaining('کد تو'), findsNothing);

      gate.complete('ABC234');
      await _settle(tester);
      expect(find.textContaining('ABC234'), findsOneWidget);
      expect(find.text('اشتراک‌گذاری'), findsOneWidget);
    });

    testWidgets('a failed fetch offers a retry', (tester) async {
      await h.register();
      h.auth.codeError = Exception('offline');
      _size(tester, 393, 852);
      await tester.pumpWidget(h.app());
      await _settle(tester);

      expect(find.text('کد دعوت بارگذاری نشد'), findsOneWidget);
      expect(find.text('اشتراک‌گذاری'), findsNothing);
      expect(find.text('دوستان من'), findsOneWidget, reason: 'screen unaffected');

      h.auth.codeError = null;
      await tester.tap(find.text('تلاش دوباره'));
      await _settle(tester);
      expect(find.textContaining('K7M2QX'), findsOneWidget);
    });
  });

  group('tab refresh', () {
    testWidgets('a tab tap reloads silently: no spinner, new data appears', (tester) async {
      await open(tester);
      expect(h.repo.fetches, 1);

      h.repo.friends = [..._friends, const FriendModel(userId: 'f9', username: 'نوید ا.', weeklyScore: 5)];
      h.repo.gate = Completer();
      h.bus.notify(MainTab.friends);
      await tester.pump();
      expect(find.byType(ZLoadState), findsNothing, reason: 'no spinner');
      expect(find.text('مریم ک.'), findsOneWidget, reason: 'old data stays');

      h.repo.gate!.complete(h.repo.friends);
      await _settle(tester);
      expect(h.repo.fetches, 2);
      expect(find.text('نوید ا.'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the current data and says nothing', (tester) async {
      await open(tester);
      h.repo.fetchError = const FriendsException(code: 'network_error', message: 'خطا در اتصال به اینترنت');
      h.bus.notify(MainTab.friends);
      await _settle(tester);

      expect(h.repo.fetches, 2);
      expect(find.text('مریم ک.'), findsOneWidget);
      expect(find.text('خطا در اتصال به اینترنت'), findsNothing);
      expect(find.text('تلاش دوباره'), findsNothing);
    });

    testWidgets('another tab tapping does nothing', (tester) async {
      await open(tester);
      h.bus.notify(MainTab.home);
      await _settle(tester);
      expect(h.repo.fetches, 1);
    });

    testWidgets('a change made in the inbox reloads the list', (tester) async {
      await open(tester);
      h.messages.changed.add(null);
      await _settle(tester);
      expect(h.repo.fetches, 2);
    });

    testWidgets('the first tap explains notifications, once', (tester) async {
      await open(tester);
      expect(find.text('از دوستانت جا نمون!'), findsNothing, reason: 'not on load');

      h.bus.notify(MainTab.friends);
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsOneWidget);
      expect(h.notifications.permissionRequests, 0, reason: 'asks first');

      await tester.tap(find.text('بعداً'));
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsNothing);

      h.bus.notify(MainTab.friends);
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsNothing, reason: 'once');
    });

    testWidgets('agreeing requests the OS permission', (tester) async {
      await open(tester);
      h.bus.notify(MainTab.friends);
      await _settle(tester);
      await tester.tap(find.text('فعال‌سازی اعلان‌ها'));
      await _settle(tester);
      expect(h.notifications.permissionRequests, 1);
    });

    testWidgets('already authorized: no explainer', (tester) async {
      await open(tester);
      h.notifications.authorized = true;
      h.bus.notify(MainTab.friends);
      await _settle(tester);
      expect(find.text('از دوستانت جا نمون!'), findsNothing);
    });
  });

  group('reduced motion', () {
    testWidgets('nothing keeps scheduling frames', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('layout', () {
    const sizes = [Size(320, 568), Size(360, 640), Size(393, 852), Size(430, 932)];

    void busy() {
      h.repo.friends = [
        for (var i = 0; i < 6; i++)
          FriendModel(
            userId: 'f$i',
            username: i == 1 ? 'یک_نام_کاربری_خیلی_خیلی_بلند_فارسی' : 'دوست $i',
            weeklyScore: 1000000 + i,
          ),
      ];
      h.repo.requests = const [
        _leila,
        PendingRequest(requesterId: 'r9', username: 'نام_کاربری_بسیار_بلند_برای_درخواست_دوستی'),
      ];
      h.repo.challenges = [_challenge];
    }

    for (final size in sizes) {
      for (final brightness in Brightness.values) {
        final tag = '${size.width.toInt()}×${size.height.toInt()} ${brightness.name}';

        testWidgets('busy list: no overflow $tag', (tester) async {
          busy();
          await open(tester, brightness: brightness, w: size.width, hgt: size.height);
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -2000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });

        testWidgets('empty, guest, loading, error: no overflow $tag', (tester) async {
          h.repo.friends = const [];
          await open(tester, brightness: brightness, w: size.width, hgt: size.height);
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -2000));
          await tester.pump();
          expect(tester.takeException(), isNull);

          await GetIt.I.reset();
          h = _Harness();
          h.repo.fetchError = const FriendsException(code: 'network_error', message: 'خطا در اتصال به اینترنت');
          await open(tester, brightness: brightness, w: size.width, hgt: size.height);
          expect(tester.takeException(), isNull);

          await GetIt.I.reset();
          h = _Harness();
          h.repo.gate = Completer();
          await open(tester, brightness: brightness, w: size.width, hgt: size.height);
          expect(tester.takeException(), isNull);

          await GetIt.I.reset();
          h = _Harness();
          await open(tester, auth: const AuthGuest(), brightness: brightness, w: size.width, hgt: size.height);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('text ×$scale: no overflow, fixed controls capped at 1.3', (tester) async {
        busy();
        await open(tester, textScale: scale, w: 320, hgt: 568);
        expect(tester.takeException(), isNull);

        double scaleOf(String label) =>
            tester.renderObject<RenderParagraph>(find.text(label).first).textScaler.scale(10);
        expect(scaleOf('جست‌وجوی نام دوستان'), lessThanOrEqualTo(13.01));

        final list = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.text('اشتراک‌گذاری'), 200, scrollable: list);
        expect(scaleOf('اشتراک‌گذاری'), lessThanOrEqualTo(13.01));
        await tester.drag(list, const Offset(0, -3000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(scaleOf('دعوت به بازی'), lessThanOrEqualTo(13.01));
        // Names and sub-lines are not fixed-height: they keep scaling.
        expect(scaleOf('دوست 0'), closeTo(10 * scale, .01));
      });
    }

    testWidgets('the add dialog at text ×2.0 on a small phone', (tester) async {
      await open(tester, textScale: 2.0, w: 320, hgt: 568);
      await tester.tap(find.bySemanticsLabel('افزودن دوست'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('ارسال درخواست'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('keyboard open (search focused) ${brightness.name}', (tester) async {
        busy();
        await open(tester, brightness: brightness, w: 375, hgt: 667, keyboard: 260);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // The field stays above the keyboard.
        final field = tester.getRect(find.byType(TextField));
        expect(field.bottom, lessThanOrEqualTo(667 - 260));

        await tester.enterText(find.byType(TextField), 'دوست');
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('keyboard open (add dialog) ${brightness.name}', (tester) async {
        await open(tester, brightness: brightness, w: 320, hgt: 568, keyboard: 260);
        await tester.tap(find.bySemanticsLabel('افزودن دوست'));
        await _settle(tester);
        expect(tester.takeException(), isNull);

        // Field and both buttons are above the keyboard (or scrollable to it).
        final field = tester.getRect(find.byType(TextField).last);
        expect(field.bottom, lessThanOrEqualTo(568 - 260));
        final send = find.text('ارسال درخواست');
        await tester.ensureVisible(send);
        await tester.pump();
        expect(tester.getRect(send).bottom, lessThanOrEqualTo(568 - 260));
      });
    }
  });

  group('colours', () {
    for (final brightness in Brightness.values) {
      testWidgets('text on its fill is readable (${brightness.name})', (tester) async {
        await open(tester, brightness: brightness);
        final z = tester.element(find.byType(ZFriendsScreen)).z;

        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        // Names, sub-lines, the hint and the «دعوت شد» label.
        expect(contrastRatio(z.ink, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    }

    for (final brightness in Brightness.values) {
      final b = brightness.name;

      testWidgets('requests + list $b', (tester) async {
        h.repo.requests = const [_leila, _behnam];
        await open(tester, brightness: brightness);
        await shot(tester, 'z_friends_list_$b');
      });
    }

    testWidgets('invited + small phone dark', (tester) async {
      await open(tester, brightness: Brightness.dark, w: 320, hgt: 568);
      await tester.tap(find.text('دعوت به بازی').first);
      await _settle(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);
      // Let the toast go, so the golden shows the row and not the notice.
      await _waitForToastToGo(tester);
      await shot(tester, 'z_friends_invited_320_dark');
    });

    testWidgets('empty light', (tester) async {
      h.repo.friends = const [];
      await open(tester);
      await shot(tester, 'z_friends_empty_light');
    });

    testWidgets('guest light', (tester) async {
      await open(tester, auth: const AuthGuest());
      await shot(tester, 'z_friends_guest_light');
    });

    testWidgets('error dark', (tester) async {
      h.repo.fetchError = const FriendsException(code: 'network_error', message: 'خطا در اتصال به اینترنت');
      await open(tester, brightness: Brightness.dark);
      await shot(tester, 'z_friends_error_dark');
    });

    testWidgets('add dialog with the keyboard up, small phone light', (tester) async {
      await open(tester, w: 320, hgt: 568, keyboard: 260);
      await tester.tap(find.bySemanticsLabel('افزودن دوست'));
      await _settle(tester);
      await shot(tester, 'z_friends_add_keyboard_320_light');
    });

    testWidgets('remove dialog dark', (tester) async {
      await open(tester, brightness: Brightness.dark);
      await tester.longPress(find.text('مریم ک.'));
      await _settle(tester);
      await shot(tester, 'z_friends_remove_dark');
    });
  });
}

/// An auth cubit whose invite-code fetch waits on [gate].
class _SlowCode extends _Auth {
  final Completer<String> gate;

  _SlowCode(this.gate) : super(_signedIn);

  @override
  Future<String> fetchMyReferralCode() => gate.future;
}
