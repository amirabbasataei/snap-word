import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/utils/error_messages.dart';

class InboxException implements Exception {
  final String code;
  final String message;

  const InboxException({required this.code, required this.message});

  @override
  String toString() => 'InboxException($code): $message';
}

/// A message an admin sent to this player from the panel (the «پیام درون‌برنامه»
/// channel). Unread ones are listed until the player dismisses them.
class InboxMessage {
  final String id;
  final String title;
  final String body;

  /// A go_router path the message points at (`/daily`, `/rewards`, …); empty
  /// when it is just text.
  final String route;

  const InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    this.route = '',
  });

  factory InboxMessage.fromJson(Map<String, dynamic> json) => InboxMessage(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    body: (json['body'] as String?) ?? '',
    route: (json['route'] as String?) ?? '',
  );
}

class InboxRepository {
  final Dio _dio;

  InboxRepository({required Dio dio}) : _dio = dio;

  Future<List<InboxMessage>> fetchUnread() async {
    try {
      final response = await _dio.get(ApiEndpoints.inbox);
      final list =
          ((response.data['data'] as Map<String, dynamic>?)?['messages']
              as List<dynamic>?) ??
          const [];
      return [
        for (final e in list) InboxMessage.fromJson(e as Map<String, dynamic>),
      ];
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post(ApiEndpoints.inboxRead(id));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  InboxException _mapError(DioException e) {
    final code = apiErrorCode(e);
    return InboxException(code: code, message: errorMessageFor(code));
  }
}
