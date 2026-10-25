import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/friends/cubit/friends_cubit.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

const _maryam = FriendModel(userId: 'f1', username: 'مریم ک.', weeklyScore: 10);
const _hossein = FriendModel(userId: 'f2', username: 'حسین ط.', weeklyScore: 0);

class _Repo extends Fake implements FriendsRepository {
  List<FriendModel> friends = [_maryam, _hossein];
  List<PendingRequest> requests = const [];
  List<PendingChallenge> challenges = const [];
  Object? fetchError;
  Object? actionError;
  int fetches = 0;
  final removed = <String>[];

  @override
  Future<List<FriendModel>> fetchFriends() async {
    fetches++;
    if (fetchError != null) throw fetchError!;
    return friends;
  }

  @override
  Future<List<PendingRequest>> fetchPendingRequests() async => requests;

  @override
  Future<List<PendingChallenge>> fetchPendingChallenges() async => challenges;

  @override
  Future<void> sendFriendRequest(String username) async {
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> respondToRequest(String requesterId, bool accept) async {
    if (actionError != null) throw actionError!;
  }

  @override
  Future<void> removeFriend(String friendId) async {
    if (actionError != null) throw actionError!;
    removed.add(friendId);
    friends = [
      for (final f in friends)
        if (f.userId != friendId) f,
    ];
  }

  @override
  Future<String?> sendChallenge(String friendId, String mode) async {
    if (actionError != null) throw actionError!;
    return 'c1';
  }
}

FriendsException _err(String code) =>
    FriendsException(code: code, message: errorMessageFor(code));

/// The states a cubit emits while [body] runs.
Future<List<FriendsState>> _record(
  FriendsCubit cubit,
  Future<void> Function() body,
) async {
  final states = <FriendsState>[];
  final sub = cubit.stream.listen(states.add);
  await body();
  await pumpEventQueue();
  await sub.cancel();
  return states;
}

void main() {
  late _Repo repo;
  late FriendsCubit cubit;

  setUp(() {
    repo = _Repo();
    cubit = FriendsCubit(repository: repo);
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  group('load', () {
    test(
      'loading then loaded, challenger names taken from the friends',
      () async {
        repo.challenges = [
          PendingChallenge(
            id: 'c1',
            challengerId: 'f1',
            challengerUsername: 'f1',
            mode: 'classic',
            expiresAt: DateTime(2030),
          ),
        ];
        final states = await _record(cubit, cubit.load);

        expect(states.first, isA<FriendsLoading>());
        final loaded = states.last as FriendsLoaded;
        expect(loaded.friends, [_maryam, _hossein]);
        expect(loaded.pendingChallenges.single.challengerUsername, 'مریم ک.');
        expect(loaded.invited, isEmpty);
      },
    );

    test('a failed first load is a Persian error', () async {
      repo.fetchError = _err('network_error');
      final states = await _record(cubit, cubit.load);
      expect((states.last as FriendsError).message, networkErrorMessage);
    });

    test('an unexpected failure falls back to the generic message', () async {
      repo.fetchError = StateError('boom');
      final states = await _record(cubit, cubit.load);
      expect((states.last as FriendsError).message, loadFriendsFailedMessage);
    });

    test('a silent reload shows no spinner', () async {
      await cubit.load();
      repo.friends = [_maryam];
      final states = await _record(cubit, () => cubit.load(silent: true));

      expect(states.whereType<FriendsLoading>(), isEmpty);
      expect((states.last as FriendsLoaded).friends, [_maryam]);
    });

    test('a failed silent reload keeps what is on screen', () async {
      await cubit.load();
      final before = cubit.state;
      repo.fetchError = _err('network_error');
      final states = await _record(cubit, () => cubit.load(silent: true));

      expect(states, isEmpty);
      expect(cubit.state, before);
    });

    test(
      'a silent load before the first one still shows the spinner',
      () async {
        final states = await _record(cubit, () => cubit.load(silent: true));
        expect(states.first, isA<FriendsLoading>());
      },
    );
  });

  group('actions keep the list', () {
    test(
      'a failed friend request keeps the list and sets the reason',
      () async {
        await cubit.load();
        repo.actionError = _err('user_not_found');
        final states = await _record(
          cubit,
          () => cubit.sendFriendRequest('nobody'),
        );

        final last = states.last as FriendsLoaded;
        expect(last.friends, hasLength(2));
        expect(last.actionError, errorMessageFor('user_not_found'));
        expect(states.whereType<FriendsError>(), isEmpty);
      },
    );

    test(
      'a failed response keeps the list (it used to blank the screen)',
      () async {
        await cubit.load();
        repo.actionError = _err('request_not_found');
        final states = await _record(
          cubit,
          () => cubit.respondToRequest('r1', true),
        );

        expect(states.whereType<FriendsError>(), isEmpty);
        expect((states.last as FriendsLoaded).actionError, isNotNull);
      },
    );

    test('a failed removal keeps the list', () async {
      await cubit.load();
      repo.actionError = _err('network_error');
      final states = await _record(cubit, () => cubit.removeFriend('f1'));

      expect(states.whereType<FriendsError>(), isEmpty);
      expect((states.last as FriendsLoaded).friends, hasLength(2));
    });

    test('the same failure twice is two state changes', () async {
      await cubit.load();
      repo.actionError = _err('user_not_found');
      final states = await _record(cubit, () async {
        await cubit.sendFriendRequest('a');
        await cubit.sendFriendRequest('a');
      });

      final withError = states.whereType<FriendsLoaded>().where(
        (s) => s.actionError != null,
      );
      expect(withError, hasLength(2));
    });

    test('a coin shortfall has its own state and reloads', () async {
      await cubit.load();
      final fetches = repo.fetches;
      repo.actionError = _err('insufficient_coins');
      final states = await _record(
        cubit,
        () => cubit.sendChallenge('f1', 'classic'),
      );

      expect(states.whereType<FriendsInsufficientCoins>(), hasLength(1));
      expect(repo.fetches, fetches + 1);
      expect((cubit.state as FriendsLoaded).invited, isEmpty);
    });

    test('removing a friend reloads without a spinner', () async {
      await cubit.load();
      final states = await _record(cubit, () => cubit.removeFriend('f1'));

      expect(repo.removed, ['f1']);
      expect(states.whereType<FriendsLoading>(), isEmpty);
      expect((states.last as FriendsLoaded).friends, [_hossein]);
    });
  });

  group('invited mark', () {
    // Under testWidgets' fake clock a future only completes when pumped.
    Future<void> run(WidgetTester tester, Future<void> call) async {
      var done = false;
      unawaited(call.whenComplete(() => done = true));
      for (var i = 0; i < 5 && !done; i++) {
        await tester.pump();
      }
      expect(done, isTrue);
    }

    // The mark's timer must not outlive the test.
    Future<void> end(WidgetTester tester) async {
      unawaited(cubit.close());
      await tester.pump();
    }

    testWidgets('is set on send and wears off', (tester) async {
      await run(tester, cubit.load());
      await run(tester, cubit.sendChallenge('f1', 'classic'));

      expect((cubit.state as FriendsLoaded).invited, {'f1'});

      await tester.pump(
        const Duration(seconds: GameConstants.friendInviteSentSec - 1),
      );
      expect((cubit.state as FriendsLoaded).invited, {'f1'});

      await tester.pump(const Duration(seconds: 2));
      expect((cubit.state as FriendsLoaded).invited, isEmpty);
      await end(tester);
    });

    testWidgets('survives a reload, and a resend restarts the clock', (
      tester,
    ) async {
      await run(tester, cubit.load());
      await run(tester, cubit.sendChallenge('f1', 'classic'));
      await run(tester, cubit.load(silent: true));
      expect((cubit.state as FriendsLoaded).invited, {'f1'});

      await tester.pump(
        const Duration(seconds: GameConstants.friendInviteSentSec - 10),
      );
      await run(tester, cubit.sendChallenge('f1', 'classic'));
      await tester.pump(const Duration(seconds: 20));
      expect((cubit.state as FriendsLoaded).invited, {'f1'});
      await end(tester);
    });

    testWidgets('removing the friend drops the mark', (tester) async {
      await run(tester, cubit.load());
      await run(tester, cubit.sendChallenge('f1', 'classic'));
      await run(tester, cubit.removeFriend('f1'));
      expect((cubit.state as FriendsLoaded).invited, isEmpty);
      await end(tester);
    });

    testWidgets('closing the cubit cancels the timer', (tester) async {
      await run(tester, cubit.load());
      await run(tester, cubit.sendChallenge('f1', 'classic'));
      await end(tester);
      expect(cubit.isClosed, isTrue);
      // A pending timer would fail the test at teardown.
    });
  });
}
