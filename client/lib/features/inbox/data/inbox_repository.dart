import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class InboxException implements Exception {
  final String code;
  const InboxException(this.code);
}

/// A "your friend joined with your code" message with a claimable bonus.
class InboxItem {
  final String id;
  final String username;
  final int coins;
  final bool claimed;
  final DateTime createdAt;

  const InboxItem({
    required this.id,
    required this.username,
    required this.coins,
    required this.claimed,
    required this.createdAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> json) => InboxItem(
        id: json['id'] as String,
        username: json['username'] as String? ?? '',
        coins: json['coins'] as int? ?? 0,
        claimed: json['claimed'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  InboxItem asClaimed() => InboxItem(
        id: id,
        username: username,
        coins: coins,
        claimed: true,
        createdAt: createdAt,
      );
}

class InboxRepository {
  final Dio _dio;

  InboxRepository({required Dio dio}) : _dio = dio;

  Future<List<InboxItem>> fetch() async {
    try {
      final response = await _dio.get(ApiEndpoints.inbox);
      final data = response.data['data'] as Map<String, dynamic>;
      return (data['items'] as List<dynamic>)
          .map((e) => InboxItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw InboxException(e.response?.data?['error']?['code'] as String? ?? 'network');
    }
  }

  /// Returns the coins credited.
  Future<int> claim(String id) async {
    try {
      final response = await _dio.post(ApiEndpoints.inboxClaim(id));
      return (response.data['data'] as Map<String, dynamic>)['coins_awarded'] as int;
    } on DioException catch (e) {
      throw InboxException(e.response?.data?['error']?['code'] as String? ?? 'network');
    }
  }
}
