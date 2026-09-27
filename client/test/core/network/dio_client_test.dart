import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/network/dio_client.dart';

/// A fake transport that rejects any Authorization header other than
/// [validToken] with 401, and answers /auth/refresh with a fixed new token —
/// letting tests drive the real [DioClient] interceptor without a server.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.validToken);

  String validToken;
  int refreshCalls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh')) {
      refreshCalls++;
      validToken = 'new-token';
      return _json(200, {
        'data': {'access_token': validToken, 'refresh_token': 'new-refresh'},
      });
    }

    final auth = options.headers['Authorization'] as String?;
    if (auth != 'Bearer $validToken') {
      return _json(401, {
        'error': {'code': 'invalid_token', 'message': 'token is invalid or expired'},
      });
    }
    return _json(200, {
      'data': {'ok': true},
    });
  }

  ResponseBody _json(int status, Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('concurrent 401s share one refresh and all retry successfully', () async {
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'expired-token',
      'jwt_refresh_token': 'valid-refresh-token',
    });
    final prefs = await SharedPreferences.getInstance();
    final client = DioClient(prefs);
    final adapter = _FakeAdapter('new-token'); // old stored token is stale
    client.dio.httpClientAdapter = adapter;

    final results = await Future.wait([
      client.dio.get('/api/v1/daily'),
      client.dio.get('/api/v1/leaderboard'),
      client.dio.get('/api/v1/profile/stats'),
    ]);

    expect(adapter.refreshCalls, 1,
        reason: 'all concurrent 401s should share a single refresh call');
    expect(results.every((r) => r.statusCode == 200), isTrue,
        reason: 'every request that failed on the stale token should be retried and succeed');
    expect(prefs.getString('jwt_access_token'), 'new-token');
  });

  test('a refresh-endpoint network error leaves stored tokens intact', () async {
    SharedPreferences.setMockInitialValues({
      'jwt_access_token': 'expired-token',
      'jwt_refresh_token': 'valid-refresh-token',
    });
    final prefs = await SharedPreferences.getInstance();
    final client = DioClient(prefs);
    client.dio.httpClientAdapter = _ThrowingRefreshAdapter();

    await expectLater(client.dio.get('/api/v1/daily'), throwsA(isA<DioException>()));

    expect(prefs.getString('jwt_refresh_token'), 'valid-refresh-token',
        reason: 'a transient failure refreshing must not log the user out');
  });
}

class _ThrowingRefreshAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/refresh')) {
      throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 10),
        requestOptions: options,
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'error': {'code': 'invalid_token', 'message': 'token is invalid or expired'},
      }),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
