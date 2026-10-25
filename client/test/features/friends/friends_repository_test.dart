import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/friends/data/friends_repository.dart';

/// Answers each path with a canned body; a path mapped to `null` is a 500.
class _Adapter implements HttpClientAdapter {
  final Map<String, Object?> routes;

  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = routes.keys.firstWhere(
      (k) => options.uri.path.endsWith(k),
      orElse: () => '',
    );
    final body = routes[key];
    if (key.isEmpty || body == null) {
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

FriendsRepository _repo(Map<String, Object?> routes) =>
    FriendsRepository(dio: Dio()..httpClientAdapter = _Adapter(routes));

const _friendRows = [
  {'user_id': 'f1', 'username': 'مریم', 'friend_since': '2026-01-01T00:00:00Z'},
  {'user_id': 'f2', 'username': 'حسین', 'friend_since': '2026-01-02T00:00:00Z'},
  {'user_id': 'f3', 'username': 'سینا', 'friend_since': '2026-01-03T00:00:00Z'},
];

void main() {
  test(
    'a friend gets this week\'s score and the premium avatar of the board',
    () async {
      final friends =
          await _repo({
            '/friends': _friendRows,
            '/leaderboard': {
              'entries': [
                {
                  'rank': 1,
                  'user_id': 'f1',
                  'username': 'مریم',
                  'score': 1840.0,
                  'avatar_id': 'fox',
                },
                {'rank': 2, 'user_id': 'me', 'username': 'من', 'score': 10.0},
                {
                  'rank': 3,
                  'user_id': 'f2',
                  'username': 'حسین',
                  'score': 0.0,
                  'avatar_id': '',
                },
              ],
            },
          }).fetchFriends();

      expect(friends.map((f) => f.username), ['مریم', 'حسین', 'سینا']);
      expect(friends[0].weeklyScore, 1840);
      expect(friends[0].avatarId, 'fox');
      expect(friends[1].avatarId, isNull, reason: 'free / lapsed: none');
      expect(friends[2].weeklyScore, 0, reason: 'not on the board');
      expect(friends[2].avatarId, isNull);
    },
  );

  test('a board that fails still lists the friends, with no scores', () async {
    final friends =
        await _repo({
          '/friends': _friendRows,
          '/leaderboard': null,
        }).fetchFriends();

    expect(friends, hasLength(3));
    expect(
      friends.every((f) => f.weeklyScore == 0 && f.avatarId == null),
      isTrue,
    );
  });

  test('a failed friends call is a Persian FriendsException', () async {
    await expectLater(
      _repo({'/friends': null}).fetchFriends(),
      throwsA(
        isA<FriendsException>().having((e) => e.code, 'code', 'internal_error'),
      ),
    );
  });
}
