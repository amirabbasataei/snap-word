import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class FriendsException implements Exception {
  final String code;
  final String message;

  const FriendsException({required this.code, required this.message});

  @override
  String toString() => 'FriendsException($code): $message';
}

class FriendModel {
  final String userId;
  final String username;
  final int weeklyScore;

  const FriendModel({
    required this.userId,
    required this.username,
    required this.weeklyScore,
  });

  factory FriendModel.fromJson(Map<String, dynamic> json,
      {int weeklyScore = 0}) =>
      FriendModel(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        weeklyScore: weeklyScore,
      );
}

class PendingRequest {
  final String requesterId;
  final String username;

  const PendingRequest({
    required this.requesterId,
    required this.username,
  });

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
        requesterId: json['requester_id'] as String,
        username: json['username'] as String,
      );
}

class PendingChallenge {
  final String id;
  final String challengerId;
  final String challengerUsername;
  final String mode;
  final DateTime expiresAt;

  const PendingChallenge({
    required this.id,
    required this.challengerId,
    required this.challengerUsername,
    required this.mode,
    required this.expiresAt,
  });

  factory PendingChallenge.fromJson(
    Map<String, dynamic> json, {
    String? challengerUsername,
  }) =>
      PendingChallenge(
        id: json['id'] as String,
        challengerId: json['challenger_id'] as String,
        challengerUsername: challengerUsername ?? json['challenger_id'] as String,
        mode: json['mode'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class FriendsRepository {
  final Dio _dio;

  FriendsRepository({required Dio dio}) : _dio = dio;

  Future<List<FriendModel>> fetchFriends() async {
    try {
      final friendsResp = await _dio.get(ApiEndpoints.friends);
      final friendList = (friendsResp.data['data'] as List<dynamic>?) ?? [];

      // Fetch friends leaderboard scores
      Map<String, int> scoreMap = {};
      try {
        final lbResp = await _dio.get(
          ApiEndpoints.leaderboard,
          queryParameters: {'type': 'friends', 'limit': 100},
        );
        final entries =
            (lbResp.data['data']?['entries'] as List<dynamic>?) ?? [];
        for (final e in entries) {
          final m = e as Map<String, dynamic>;
          scoreMap[m['user_id'] as String] =
              (m['score'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {
        // Scores unavailable — show 0
      }

      return friendList
          .map((e) => FriendModel.fromJson(
                e as Map<String, dynamic>,
                weeklyScore: scoreMap[e['user_id'] as String] ?? 0,
              ))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<PendingRequest>> fetchPendingRequests() async {
    try {
      final response = await _dio.get(ApiEndpoints.friendsRequests);
      final list = (response.data['data'] as List<dynamic>?) ?? [];
      return list
          .map((e) =>
              PendingRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<PendingChallenge>> fetchPendingChallenges() async {
    try {
      final response = await _dio.get(ApiEndpoints.challengesPending);
      final list = (response.data['data'] as List<dynamic>?) ?? [];
      return list
          .map((e) =>
              PendingChallenge.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> sendFriendRequest(String username) async {
    try {
      await _dio.post(
        ApiEndpoints.friendsRequest,
        data: {'username': username},
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> respondToRequest(String requesterId, bool accept) async {
    try {
      await _dio.post(
        ApiEndpoints.friendsRespond,
        data: {
          'requester_id': requesterId,
          'action': accept ? 'accept' : 'decline',
        },
      );
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _dio.delete(ApiEndpoints.removeFriend(friendId));
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<String?> sendChallenge(String friendId, String mode) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.challenges,
        data: {'challenged_id': friendId, 'mode': mode},
      );
      return response.data['data']?['id'] as String?;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<String?> respondToChallenge(String challengeId, bool accept) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.respondChallenge(challengeId),
        data: {'action': accept ? 'accept' : 'decline'},
      );
      return response.data['data']?['room_id'] as String?;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  FriendsException _mapError(DioException e) {
    final code =
        e.response?.data?['error']?['code'] as String? ?? 'unknown_error';
    final message = e.response?.data?['error']?['message'] as String? ??
        'An error occurred.';
    return FriendsException(code: code, message: message);
  }
}
