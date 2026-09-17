import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class LobbyException implements Exception {
  final String message;
  const LobbyException(this.message);
}

// POST /match/queue's 200 payload — the server has already resolved the
// match (human pair or AI fallback) by the time this comes back; there is
// no further "found" signal to wait for.
class MatchQueueResult {
  final String roomId;
  final bool isAi;

  const MatchQueueResult({required this.roomId, required this.isAi});
}

// Machine-readable error codes from match.go, mapped to Persian — mirrors
// the pattern already used for auth/OTP error codes (see _mapOtpError in
// z_otp_verify_screen.dart) rather than surfacing the server's raw English
// `message` field.
const _errorCodeMessages = {
  'no_match': 'حریفی پیدا نشد. دوباره تلاش کن.',
  'invalid_mode': 'نوع بازی نامعتبر است',
};

class LobbyRepository {
  final Dio _dio;

  LobbyRepository({required Dio dio}) : _dio = dio;

  // Backend note (matchmaking.go): Join() deliberately long-polls, blocking
  // the HTTP response for up to AIFallbackWaitSec+5 (35s) while it waits for
  // a human pairing or the AI fallback to fire. The app-wide Dio instance's
  // 10s receiveTimeout (dio_client.dart) is far too short for this specific
  // call — every non-instant match (i.e. the AI-fallback path this screen's
  // own copy advertises) would otherwise always time out client-side before
  // the server can respond. Override per-request rather than raising the
  // global default, so other endpoints keep failing fast on a real hang.
  static const _joinQueueTimeout = Duration(seconds: 40);

  Future<MatchQueueResult> joinQueue(String mode) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.matchQueue,
        data: {'mode': mode},
        options: Options(receiveTimeout: _joinQueueTimeout, sendTimeout: _joinQueueTimeout),
      );
      final data = response.data['data'] as Map<String, dynamic>;
      return MatchQueueResult(roomId: data['room_id'] as String, isAi: data['is_ai'] as bool? ?? false);
    } on DioException catch (e) {
      final code = e.response?.data?['error']?['code'] as String?;
      throw LobbyException(_errorCodeMessages[code] ?? 'پیوستن به صف ناموفق بود');
    }
  }

  Future<void> cancelQueue() async {
    try {
      await _dio.delete(ApiEndpoints.matchQueue);
    } on DioException catch (_) {
      // Best-effort cancellation; ignore errors
    }
  }
}
