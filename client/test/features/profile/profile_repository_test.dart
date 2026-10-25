import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/profile/data/profile_repository.dart';

/// Answers each path with a canned status + body.
class _Adapter implements HttpClientAdapter {
  final Map<String, (int, Object)> routes;
  final calls = <String>[];

  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.uri.path}');
    final hit = routes.entries.firstWhere(
      (e) => options.uri.path.endsWith(e.key),
      orElse: () => const MapEntry('', (500, {})),
    );
    final (status, body) = hit.value;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProfileRepository _repo(Map<String, (int, Object)> routes) =>
    ProfileRepository(dio: Dio()..httpClientAdapter = _Adapter(routes));

Map<String, Object> _err(String code) => {
  'error': {'code': code, 'message': 'x'},
};

void main() {
  test('stats are parsed with the level fields', () async {
    final stats =
        await _repo({
          '/profile/stats': (
            200,
            {
              'data': {
                'total_matches': 7,
                'wins': 0,
                'longest_word': 'کتابخانه',
                'best_match_streak': 0,
                'daily_streak': 2,
                'longest_daily_streak': 4,
                'xp': 2620,
                'level': 3,
                'xp_in_level': 620,
                'xp_for_next': 1000,
              },
            },
          ),
        }).fetchStats();
    expect(stats.totalMatches, 7);
    expect(stats.longestWord, 'کتابخانه');
    expect(stats.dailyStreak, 2);
    expect(stats.level, 3);
    expect(stats.xpInLevel, 620);
    expect(stats.xpForNext, 1000);
    // The server sends neither a best score nor a balance on this endpoint.
    expect(stats.bestScore, 0);
    expect(stats.coins, 0);
  });

  test('a server failure becomes the Persian load message', () async {
    await expectLater(
      _repo({'/profile/stats': (500, _err('internal_error'))}).fetchStats(),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'message',
          isNot(contains('internal')),
        ),
      ),
    );
  });

  test('perks: premium state and avatar', () async {
    final perks =
        await _repo({
          '/profile/perks': (
            200,
            {
              'data': {
                'is_premium': true,
                'premium_until': '2026-11-03T12:00:00Z',
                'avatar_id': 'fox',
              },
            },
          ),
        }).fetchPerks();
    expect(perks.isPremium, isTrue);
    expect(perks.premiumUntil, DateTime.utc(2026, 11, 3, 12));
    expect(perks.avatarId, 'fox');
  });

  test('perks: an empty avatar id is no avatar', () async {
    final perks =
        await _repo({
          '/profile/perks': (
            200,
            {
              'data': {
                'is_premium': false,
                'premium_until': null,
                'avatar_id': '',
              },
            },
          ),
        }).fetchPerks();
    expect(perks.isPremium, isFalse);
    expect(perks.avatarId, isNull);
  });

  test('a free player picking an avatar gets the Persian refusal', () async {
    await expectLater(
      _repo({
        '/profile/avatar': (403, _err('premium_required')),
      }).setAvatar('fox'),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'message',
          errorMessageFor('premium_required'),
        ),
      ),
    );
  });

  test('an unknown avatar is refused in Persian too', () async {
    await expectLater(
      _repo({
        '/profile/avatar': (400, _err('invalid_avatar')),
      }).setAvatar('nope'),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'message',
          errorMessageFor('invalid_avatar'),
        ),
      ),
    );
  });

  test('setAvatar sends a PATCH', () async {
    final adapter = _Adapter({
      '/profile/avatar': (
        200,
        {
          'data': {'avatar_id': 'fox'},
        },
      ),
    });
    await ProfileRepository(
      dio: Dio()..httpClientAdapter = adapter,
    ).setAvatar('fox');
    expect(adapter.calls, ['PATCH /api/v1/profile/avatar']);
  });
}
