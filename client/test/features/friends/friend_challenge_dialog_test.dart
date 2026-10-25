import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:wordchain/core/theme/app_scene_tokens.dart';
import 'package:wordchain/core/theme/app_tokens.dart';
import 'package:wordchain/core/utils/tab_refresh.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/friends/view/friend_challenge_dialog.dart';
import 'package:wordchain/features/friends/view/z_friends_screen.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/messages/cubit/messages_cubit.dart';

import '../../helpers/contrast.dart';
import '../../helpers/game_fakes.dart';
import '../../helpers/z_test_app.dart';

const _me = AuthAuthenticated(userId: 'me-1', username: 'آرش', coins: 100);

Widget _opener(
  void Function(bool) onResult, {
  String friend = 'مریم ک.',
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => zTestApp(
  Builder(
    builder:
        (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed:
                    () async => onResult(
                      await showFriendChallengeDialog(
                        context,
                        friendUsername: friend,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
  ),
  brightness: brightness,
  reduceMotion: true,
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void _size(WidgetTester tester, double w, double h) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

class _FakeFriends extends Fake implements FriendsRepository {
  final sent = <(String, String)>[];

  @override
  Future<List<FriendModel>> fetchFriends() async => const [
    FriendModel(userId: 'friend-7', username: 'مریم ک.', weeklyScore: 120),
  ];

  @override
  Future<List<PendingRequest>> fetchPendingRequests() async => const [];

  @override
  Future<List<PendingChallenge>> fetchPendingChallenges() async => const [];

  @override
  Future<String?> sendChallenge(String friendId, String mode) async {
    sent.add((friendId, mode));
    return null;
  }
}

class _FakeMessages extends Fake implements MessagesCubit {
  @override
  Stream<void> get friendsChanged => const Stream.empty();

  @override
  void setPending(List<PendingRequest> requests, List<PendingChallenge> challenges) {}
}

void main() {
  setUpAll(loadVazirmatn);

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<AuthCubit>(FakeAuthCubit(_me));
  });
  tearDown(GetIt.I.reset);

  group('copy', () {
    testWidgets('names who plays whom and what it costs', (tester) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_opener((_) {}));
      await _open(tester);

      expect(
        find.text(FriendChallengeDialog.titleFor('مریم ک.')),
        findsOneWidget,
      );
      expect(find.text('ورودی'), findsOneWidget);
      expect(find.text('جایزهٔ برنده'), findsOneWidget);
      expect(find.text('۲۰ سکه'), findsOneWidget);
      expect(find.text('۴۰ سکه'), findsOneWidget);
      // My initial and the friend's.
      expect(find.text('آ'), findsOneWidget);
      expect(find.text('م'), findsOneWidget);
      expect(find.text('بی‌خیال'), findsOneWidget);
      expect(find.text('بفرست'), findsOneWidget);
    });

    test('numbers come from the game constants', () {
      expect(GameConstants.entryFeeCoins, 20);
      expect(GameConstants.entryFeePot, 40);
      expect(GameConstants.challengeValidHours, 24);
    });

    test('says the invite lasts 24 hours, not 2 minutes', () {
      expect(FriendChallengeDialog.body, contains('۲۴ ساعت'));
      expect(FriendChallengeDialog.body, isNot(contains('دقیقه')));
    });

    test('the fee is taken when the match starts, not on accept', () {
      expect(FriendChallengeDialog.feeNote, contains('بازی شروع بشه'));
      expect(FriendChallengeDialog.feeNote, isNot(contains('قبول')));
    });

    testWidgets('a Latin username stays inside its sentence', (tester) async {
      _size(tester, 396, 812);
      await tester.pumpWidget(_opener((_) {}, friend: 'sina_99'));
      await _open(tester);
      expect(find.textContaining('sina_99'), findsOneWidget);
      // Initial of a Latin name is upper-cased, like the friends list.
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('a signed-out player gets the neutral initial', (tester) async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<AuthCubit>(FakeAuthCubit());
      _size(tester, 396, 812);
      await tester.pumpWidget(_opener((_) {}));
      await _open(tester);
      expect(find.text('ت'), findsOneWidget);
    });
  });

  group('result', () {
    testWidgets('«بفرست» resolves true', (tester) async {
      _size(tester, 396, 812);
      bool? result;
      await tester.pumpWidget(_opener((r) => result = r));
      await _open(tester);
      await tester.tap(find.text('بفرست'));
      await _settle(tester);
      expect(result, isTrue);
      expect(find.text('بفرست'), findsNothing);
    });

    testWidgets('«بی‌خیال» resolves false', (tester) async {
      _size(tester, 396, 812);
      bool? result;
      await tester.pumpWidget(_opener((r) => result = r));
      await _open(tester);
      await tester.tap(find.text('بی‌خیال'));
      await _settle(tester);
      expect(result, isFalse);
    });

    testWidgets('a tap on the scrim cancels', (tester) async {
      _size(tester, 396, 812);
      bool? result;
      await tester.pumpWidget(_opener((r) => result = r));
      await _open(tester);
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
      expect(result, isFalse);
    });
  });

  group('through the Friends screen', () {
    late _FakeFriends repo;

    Future<void> pumpScreen(WidgetTester tester) async {
      repo = _FakeFriends();
      GetIt.I
        ..registerSingleton<FriendsRepository>(repo)
        ..registerSingleton<MessagesCubit>(_FakeMessages())
        ..registerSingleton<TabRefreshBus>(TabRefreshBus());
      _size(tester, 396, 812);
      await tester.pumpWidget(zTestApp(const ZFriendsScreen(), reduceMotion: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('confirming sends the same classic challenge as before', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.text('دعوت به بازی'));
      await _settle(tester);
      expect(repo.sent, isEmpty, reason: 'nothing is sent before confirming');

      await tester.tap(find.text('بفرست'));
      await _settle(tester);
      expect(repo.sent, [('friend-7', 'classic')]);
    });

    testWidgets('cancelling sends nothing', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('دعوت به بازی'));
      await _settle(tester);
      await tester.tap(find.text('بی‌خیال'));
      await _settle(tester);
      expect(repo.sent, isEmpty);
    });
  });

  group('layout', () {
    for (final b in Brightness.values) {
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(393, 852),
        Size(430, 932),
      ]) {
        testWidgets(
          'no overflow ${size.width.toInt()}×${size.height.toInt()} ${b.name}',
          (tester) async {
            _size(tester, size.width, size.height);
            await tester.pumpWidget(_opener((_) {}, brightness: b));
            await _open(tester);
            expect(tester.takeException(), isNull);
            expect(find.text('بفرست'), findsOneWidget);
          },
        );
      }
    }

    testWidgets('a 32-letter username and 1.6× text still fit', (tester) async {
      _size(tester, 320, 568);
      await tester.pumpWidget(
        _opener(
          (_) {},
          friend: 'a_very_long_username_of_32_chars!',
          textScale: 1.6,
        ),
      );
      await _open(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('contrast', () {
    for (final b in Brightness.values) {
      test('pairings (${b.name})', () {
        final z = b == Brightness.light ? ZColors.light : ZColors.dark;
        final zs = b == Brightness.light ? ZScene.light : ZScene.dark;
        expect(contrastRatio(z.ink, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.wash), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.ink60, z.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onAmber, z.amber), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(z.onIndigo, z.indigo), greaterThanOrEqualTo(3));
        expect(contrastRatio(zs.onCoralSm, z.coral), greaterThanOrEqualTo(3));
        // «بفرست» is 17sp / 900: large text.
        expect(contrastRatio(z.onTeal, z.teal), greaterThanOrEqualTo(3));
      });
    }
  });

  group('goldens', () {
    for (final b in Brightness.values) {
      testWidgets('dialog ${b.name}', (tester) async {
        _size(tester, 396, 812);
        await tester.pumpWidget(_opener((_) {}, brightness: b));
        await _open(tester);
        await expectLater(
          find.byType(View).first,
          matchesGoldenFile('goldens/friend_challenge_dialog_${b.name}.png'),
        );
      });
    }
  });
}
