import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/leaderboard/data/leaderboard_repository.dart';

/// Answers each path with a canned body; a path mapped to `null` is a 500.
/// `type=` is part of the key for `/leaderboard`.
class _Adapter implements HttpClientAdapter {
  final Map<String, Object?> routes;
  final requests = <Uri>[];

  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final type = options.uri.queryParameters['type'];
    final key = type == null ? options.uri.path : '${options.uri.path}?$type';
    final body = routes[key];
    if (body == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'internal_error', 'message': 'x'},
        }),
        500,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'data': body}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(LeaderboardRepository, _Adapter) _repo(Map<String, Object?> routes) {
  final adapter = _Adapter(routes);
  return (
    LeaderboardRepository(dio: Dio()..httpClientAdapter = adapter),
    adapter,
  );
}

Map<String, Object?> _row(
  int rank,
  String id,
  num score, {
  String? avatar,
  int? chain,
}) => {
  'rank': rank,
  'user_id': id,
  'username': 'u$id',
  'score': score,
  if (avatar != null) 'avatar_id': avatar,
  if (chain != null) 'chain_length': chain,
};

void main() {
  test('weekly: entries, the server rank/score and the avatar', () async {
    final (repo, adapter) = _repo({
      '/api/v1/leaderboard?global': {
        'entries': [_row(1, 'a', 5300.0, avatar: 'fox'), _row(2, 'b', 4100.0)],
        'player_rank': 14,
        'player_score': 1840.0,
        'player_avatar_id': 'owl',
      },
    });
    final board = await repo.fetchGlobal();
    expect(board.entries.map((e) => e.userId), ['a', 'b']);
    expect(board.entries.first.avatarId, 'fox');
    expect(board.entries.last.avatarId, isNull);
    expect(board.entries.first.score, 5300);
    expect(board.entries.first.chainLength, isNull);
    expect(board.playerRank, 14);
    expect(board.playerScore, 1840);
    expect(board.playerAvatarId, 'owl');
    expect(board.dayNumber, isNull);
    expect(adapter.requests.single.queryParameters, {
      'type': 'global',
      'limit': '100',
    });
  });

  test('all-time asks for type=alltime', () async {
    final (repo, adapter) = _repo({
      '/api/v1/leaderboard?alltime': {
        'entries': [_row(1, 'a', 90000)],
        'player_rank': 0,
        'player_score': 0,
      },
    });
    final board = await repo.fetchAllTime();
    expect(board.playerRank, 0);
    expect(board.entries.single.score, 90000);
    expect(adapter.requests.single.queryParameters['type'], 'alltime');
  });

  test('friends: the player\'s place is read from the entries, not from the '
      'server\'s global weekly rank', () async {
    final (repo, _) = _repo({
      '/api/v1/leaderboard?friends': {
        'entries': [
          _row(1, 'f1', 900),
          _row(2, 'me', 300, avatar: 'cat'),
          _row(3, 'f2', 0),
        ],
        // The handler answers with the *global* rank here.
        'player_rank': 87,
        'player_score': 300.0,
        'player_avatar_id': 'cat',
      },
    });
    final board = await repo.fetchFriends('me');
    expect(board.playerRank, 2);
    expect(board.playerScore, 300);
    expect(board.playerAvatarId, 'cat');
  });

  test('friends: a player missing from the entries has no rank', () async {
    final (repo, _) = _repo({
      '/api/v1/leaderboard?friends': {
        'entries': [_row(1, 'f1', 900)],
        'player_rank': 0,
        'player_score': 0,
      },
    });
    final board = await repo.fetchFriends('me');
    expect(board.playerRank, 0);
    expect(board.playerScore, isNull);
  });

  test(
    'daily: chain length, day number, my_rank and my entry\'s score',
    () async {
      final (repo, adapter) = _repo({
        '/api/v1/daily/leaderboard': {
          'challenge_date': '2026-10-25',
          'day_number': 42,
          'entries': [
            _row(1, 'a', 480, chain: 20),
            _row(2, 'me', 410, chain: 17),
          ],
          'my_rank': 2,
        },
      });
      final board = await repo.fetchDaily('me');
      expect(board.dayNumber, 42);
      expect(board.entries.first.chainLength, 20);
      expect(board.playerRank, 2);
      expect(board.playerScore, 410);
      expect(board.playerAvatarId, isNull);
      expect(adapter.requests.single.path, endsWith('/daily/leaderboard'));
    },
  );

  test(
    'daily: below the top 100 the rank is known but the score is not',
    () async {
      final (repo, _) = _repo({
        '/api/v1/daily/leaderboard': {
          'day_number': 3,
          'entries': [_row(1, 'a', 480, chain: 20)],
          'my_rank': 140,
        },
      });
      final board = await repo.fetchDaily('me');
      expect(board.playerRank, 140);
      expect(board.playerScore, isNull);
    },
  );

  test('daily: not played yet — my_rank is null', () async {
    final (repo, _) = _repo({
      '/api/v1/daily/leaderboard': {
        'day_number': 3,
        'entries': <Object>[],
        'my_rank': null,
      },
    });
    final board = await repo.fetchDaily('me');
    expect(board.entries, isEmpty);
    expect(board.playerRank, 0);
    expect(board.playerScore, isNull);
  });

  test('a failed call throws a Persian LeaderboardException', () async {
    final (repo, _) = _repo({});
    await expectLater(
      repo.fetchGlobal(),
      throwsA(
        isA<LeaderboardException>().having(
          (e) => e.message,
          'message',
          isNot(contains('x')),
        ),
      ),
    );
    await expectLater(
      repo.fetchDaily('me'),
      throwsA(isA<LeaderboardException>()),
    );
    expect(loadLeaderboardFailedMessage, isNotEmpty);
  });
}
