import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/leaderboard/cubit/leaderboard_cubit.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

LeaderboardResult _board(String tag, {String? avatar}) => LeaderboardResult(
  entries: [LeaderboardEntry(userId: tag, username: tag, score: 10, rank: 1)],
  playerRank: 1,
  playerScore: 10,
  playerAvatarId: avatar,
);

class _Repo extends Fake implements LeaderboardRepository {
  final calls = <String>[];
  final fail = <String>{};
  final gates = <String, Completer<LeaderboardResult>>{};
  String version = 'v1';

  Future<LeaderboardResult> _answer(String tab, {String? avatar}) async {
    calls.add(tab);
    final gate = gates[tab];
    if (gate != null) return gate.future;
    if (fail.contains(tab)) {
      throw const LeaderboardException('بارگذاری جدول امتیازها ناموفق بود');
    }
    return _board('$tab-$version', avatar: avatar);
  }

  @override
  Future<LeaderboardResult> fetchGlobal() => _answer('weekly', avatar: 'fox');

  @override
  Future<LeaderboardResult> fetchAllTime() => _answer('allTime');

  @override
  Future<LeaderboardResult> fetchDaily(String currentUserId) =>
      _answer('daily');

  @override
  Future<LeaderboardResult> fetchFriends(String currentUserId) =>
      _answer('friends');
}

String _first(LeaderboardState s, BoardTab t) =>
    s.boards[t]!.entries.first.userId;

void main() {
  late _Repo repo;
  late LeaderboardCubit cubit;

  setUp(() {
    repo = _Repo();
    cubit = LeaderboardCubit(repository: repo, currentUserId: 'me');
  });

  tearDown(() => cubit.close());

  test('starts on the weekly tab with nothing loaded', () {
    expect(cubit.state.tab, BoardTab.weekly);
    expect(cubit.state.boards, isEmpty);
    expect(cubit.state.current, isNull);
  });

  test('load fetches only the visible tab and shows a spinner first', () async {
    final gate = repo.gates['weekly'] = Completer();
    final f = cubit.load();
    expect(cubit.state.loading, {BoardTab.weekly});
    gate.complete(_board('w'));
    await f;
    expect(cubit.state.loading, isEmpty);
    expect(_first(cubit.state, BoardTab.weekly), 'w');
    expect(repo.calls, ['weekly']);
  });

  test('select shows the tab at once and loads it once per visit', () async {
    await cubit.load();
    await cubit.select(BoardTab.daily);
    expect(cubit.state.tab, BoardTab.daily);
    expect(cubit.state.boards.keys, {BoardTab.weekly, BoardTab.daily});
    expect(repo.calls, ['weekly', 'daily']);
    await cubit.select(BoardTab.weekly);
    // A tab with a result keeps it while it refreshes.
    expect(repo.calls, ['weekly', 'daily', 'weekly']);
  });

  test(
    'select keeps the old result on screen while the new one loads',
    () async {
      await cubit.load();
      repo.version = 'v2';
      final gate = repo.gates['weekly'] = Completer();
      final f = cubit.select(BoardTab.weekly);
      expect(_first(cubit.state, BoardTab.weekly), 'weekly-v1');
      expect(cubit.state.loading, isEmpty);
      gate.complete(_board('weekly-v2'));
      await f;
      expect(_first(cubit.state, BoardTab.weekly), 'weekly-v2');
    },
  );

  test('every tab calls its own endpoint', () async {
    for (final t in BoardTab.values) {
      await cubit.select(t);
    }
    expect(repo.calls, ['weekly', 'daily', 'allTime', 'friends']);
  });

  test(
    'a first-load failure is kept per tab; the other tabs are unaffected',
    () async {
      repo.fail.add('daily');
      await cubit.load();
      await cubit.select(BoardTab.daily);
      expect(cubit.state.errors, {
        BoardTab.daily: loadLeaderboardFailedMessage,
      });
      expect(cubit.state.current, isNull);
      expect(cubit.state.boards.containsKey(BoardTab.weekly), isTrue);
      await cubit.select(BoardTab.weekly);
      expect(cubit.state.errors, isNotEmpty);
      expect(cubit.state.current, isNotNull);
    },
  );

  test('retry after a failure shows a spinner, then the data', () async {
    repo.fail.add('weekly');
    await cubit.load();
    expect(cubit.state.errors.keys, {BoardTab.weekly});
    repo.fail.clear();
    final gate = repo.gates['weekly'] = Completer();
    final f = cubit.load();
    expect(cubit.state.loading, {BoardTab.weekly});
    expect(cubit.state.errors, isEmpty);
    gate.complete(_board('ok'));
    await f;
    expect(cubit.state.current, isNotNull);
    expect(cubit.state.errors, isEmpty);
  });

  test('a silent reload never shows a spinner and swaps the data in', () async {
    await cubit.load();
    repo.version = 'v2';
    final gate = repo.gates['weekly'] = Completer();
    final f = cubit.load(silent: true);
    expect(cubit.state.loading, isEmpty);
    expect(_first(cubit.state, BoardTab.weekly), 'weekly-v1');
    gate.complete(_board('weekly-v2'));
    await f;
    expect(_first(cubit.state, BoardTab.weekly), 'weekly-v2');
  });

  test(
    'a silent reload that fails keeps the data and shows no error',
    () async {
      await cubit.load();
      repo.fail.add('weekly');
      await cubit.load(silent: true);
      expect(_first(cubit.state, BoardTab.weekly), 'weekly-v1');
      expect(cubit.state.errors, isEmpty);
      expect(cubit.state.loading, isEmpty);
    },
  );

  test('a silent reload before the first load still shows the error', () async {
    repo.fail.add('weekly');
    await cubit.load(silent: true);
    expect(cubit.state.errors.keys, {BoardTab.weekly});
  });

  test(
    'a silent reload that fails does not hide an existing error card',
    () async {
      repo.fail.add('weekly');
      await cubit.load();
      final before = cubit.state;
      await cubit.load(silent: true);
      expect(cubit.state.errors, before.errors);
      expect(cubit.state.loading, isEmpty);
    },
  );

  test('an unexpected error becomes the generic Persian message', () async {
    final bad = _ThrowingRepo();
    final c = LeaderboardCubit(repository: bad, currentUserId: 'me');
    await c.load();
    expect(c.state.errors[BoardTab.weekly], loadLeaderboardFailedMessage);
    await c.close();
  });

  test('an older, slower answer cannot overwrite a newer one', () async {
    final slow = repo.gates['weekly'] = Completer();
    final first = cubit.load();
    repo.gates.remove('weekly');
    repo.version = 'v2';
    await cubit.load(silent: true);
    expect(_first(cubit.state, BoardTab.weekly), 'weekly-v2');
    slow.complete(_board('stale'));
    await first;
    expect(_first(cubit.state, BoardTab.weekly), 'weekly-v2');
  });

  test('closing mid-request emits nothing and does not throw', () async {
    final gate = repo.gates['weekly'] = Completer();
    final f = cubit.load();
    await cubit.close();
    gate.complete(_board('late'));
    await f;
  });

  test('selfAvatarId comes from whichever board reported it', () async {
    await cubit.select(BoardTab.daily);
    expect(cubit.state.selfAvatarId, isNull);
    await cubit.select(BoardTab.weekly);
    expect(cubit.state.selfAvatarId, 'fox');
    await cubit.select(BoardTab.daily);
    expect(cubit.state.selfAvatarId, 'fox');
  });
}

class _ThrowingRepo extends Fake implements LeaderboardRepository {
  @override
  Future<LeaderboardResult> fetchGlobal() async => throw StateError('boom');
}
