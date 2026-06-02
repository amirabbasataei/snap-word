import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class LobbyException implements Exception {
  final String message;
  const LobbyException(this.message);
}

class LobbyRepository {
  final Dio _dio;

  LobbyRepository({required Dio dio}) : _dio = dio;

  Future<void> joinQueue(String mode) async {
    try {
      await _dio.post(ApiEndpoints.matchQueue, data: {'mode': mode});
    } on DioException catch (e) {
      throw LobbyException(e.response?.data?['error']?['message'] as String? ?? 'Failed to join queue');
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
