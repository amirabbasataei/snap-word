import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/core/theme/app_theme.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';
import 'package:wordchain/features/messages/data/inbox_repository.dart';
import 'package:wordchain/features/messages/view/messages_screen.dart';
import 'package:wordchain/features/messages/view/widgets/announcement_tile.dart';

import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';
import '../rewards/rewards_fakes.dart';

class _Friends extends Fake implements FriendsRepository {
  List<PendingRequest> requests = const [];

  @override
  Future<List<PendingRequest>> fetchPendingRequests() async => requests;

  @override
  Future<List<PendingChallenge>> fetchPendingChallenges() async => const [];
}

class _Inbox extends Fake implements InboxRepository {
  List<InboxMessage> messages;
  bool failFetch = false;
  bool failRead = false;
  final read = <String>[];

  _Inbox(this.messages);

  @override
  Future<List<InboxMessage>> fetchUnread() async {
    if (failFetch) {
      throw const InboxException(code: 'network_error', message: 'x');
    }
    return List.of(messages);
  }

  @override
  Future<void> markRead(String id) async {
    if (failRead) {
      throw const InboxException(code: 'network_error', message: 'x');
    }
    read.add(id);
  }
}

const _promo = InboxMessage(
  id: 'm1',
  title: 'جشن هفته',
  body: 'امروز جایزهٔ دوبرابر داریم',
  route: '/daily',
);
const _plain = InboxMessage(id: 'm2', title: 'سلام', body: 'خوش آمدی');

AuthCubit _signedIn() => FakeAuthCubit(
  const AuthAuthenticated(userId: 'me', username: 'آرش', coins: 90),
);

void main() {
  setUpAll(loadVazirmatn);

  group('MessagesCubit announcements', () {
    test(
      'refresh loads admin notices and they count toward the badge',
      () async {
        final friends =
            _Friends()
              ..requests = [
                const PendingRequest(requesterId: 'r1', username: 'سارا'),
              ];
        final cubit = MessagesCubit(
          repo: friends,
          inbox: _Inbox([_promo, _plain]),
          auth: _signedIn(),
        );
        await cubit.refresh();
        expect(cubit.state.announcements.map((m) => m.id), ['m1', 'm2']);
        expect(cubit.state.count, 3); // 1 request + 2 notices
        expect(cubit.state.loaded, isTrue);
      },
    );

    test('a failing notice list never hides the friend requests', () async {
      final friends =
          _Friends()
            ..requests = [
              const PendingRequest(requesterId: 'r1', username: 'سارا'),
            ];
      final inbox = _Inbox([_promo]);
      final cubit = MessagesCubit(
        repo: friends,
        inbox: inbox,
        auth: _signedIn(),
      );
      await cubit.refresh();
      inbox.failFetch = true;
      await cubit.refresh();
      expect(cubit.state.requests, hasLength(1));
      expect(cubit.state.announcements, [_promo]); // last good copy kept
      expect(cubit.state.error, isNull);
    });

    test('dismissing removes the notice at once and marks it read', () async {
      final inbox = _Inbox([_promo, _plain]);
      final cubit = MessagesCubit(
        repo: _Friends(),
        inbox: inbox,
        auth: _signedIn(),
      );
      await cubit.refresh();
      await cubit.dismissAnnouncement(_promo);
      expect(cubit.state.announcements, [_plain]);
      expect(inbox.read, ['m1']);
    });

    test(
      'a failed mark-read still clears the card (it returns on refresh)',
      () async {
        final inbox = _Inbox([_promo])..failRead = true;
        final cubit = MessagesCubit(
          repo: _Friends(),
          inbox: inbox,
          auth: _signedIn(),
        );
        await cubit.refresh();
        await cubit.dismissAnnouncement(_promo);
        expect(cubit.state.announcements, isEmpty);
        await cubit.refresh();
        expect(cubit.state.announcements, [_promo]);
      },
    );

    test('a guest gets nothing', () async {
      final cubit = MessagesCubit(
        repo: _Friends(),
        inbox: _Inbox([_promo]),
        auth: FakeAuthCubit(const AuthGuest()),
      );
      await cubit.refresh();
      expect(cubit.state.announcements, isEmpty);
      expect(cubit.state.count, 0);
    });
  });

  group('MessagesScreen announcements', () {
    setUp(() async => GetIt.I.reset());
    tearDown(() async => GetIt.I.reset());

    Future<String?> open(WidgetTester tester, _Inbox inbox) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      final auth = _signedIn();
      GetIt.I
        ..registerSingleton<AuthCubit>(auth)
        ..registerSingleton<AdService>(FakeRewardedAds())
        ..registerSingleton<MessagesCubit>(
          MessagesCubit(repo: _Friends(), inbox: inbox, auth: auth),
        );
      String? landed;
      final router = GoRouter(
        initialLocation: '/messages',
        routes: [
          GoRoute(path: '/messages', builder: (_, _) => const MessagesScreen()),
          GoRoute(
            path: '/daily',
            builder: (_, _) {
              landed = '/daily';
              return const Scaffold(body: Text('daily'));
            },
          ),
          GoRoute(path: '/home', builder: (_, _) => const Scaffold()),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 700));
      return landed;
    }

    testWidgets('shows the notice; «باشه» clears it and tells the server', (
      tester,
    ) async {
      final inbox = _Inbox([_plain]);
      await open(tester, inbox);
      expect(find.byType(AnnouncementTile), findsOneWidget);
      expect(find.text('سلام'), findsOneWidget);
      expect(find.text('نمایش'), findsNothing); // no route → just text

      await tester.tap(find.text('باشه'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(inbox.read, ['m2']);
      expect(find.byType(AnnouncementTile), findsNothing);
    });

    testWidgets('a notice with a route opens that screen and clears itself', (
      tester,
    ) async {
      final inbox = _Inbox([_promo]);
      await open(tester, inbox);
      expect(find.text('نمایش'), findsOneWidget);
      await tester.tap(find.text('نمایش'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('daily'), findsOneWidget);
      expect(inbox.read, ['m1']);
    });
  });
}
