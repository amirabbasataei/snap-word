import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class LeaderboardException implements Exception {
  final String message;
  const LeaderboardException(this.message);
}

class LeaderboardEntry {
  final String userId;
  final String username;
  final int score;
  final int rank;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        score: (json['score'] as num).toInt(),
        rank: json['rank'] as int? ?? 0,
      );
}

class LeaderboardResult {
  final List<LeaderboardEntry> entries;
  final int playerRank;
  final int playerScore;

  const LeaderboardResult({
    required this.entries,
    required this.playerRank,
    required this.playerScore,
  });
}

class LeaderboardRepository {
  final Dio _dio;

  LeaderboardRepository({required Dio dio}) : _dio = dio;

  Future<LeaderboardResult> fetchGlobal() => _fetch('global');

  Future<LeaderboardResult> fetchFriends() => _fetch('friends');

  Future<LeaderboardResult> _fetch(String type) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.leaderboard,
        queryParameters: {'type': type, 'limit': 100},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final list = (data['entries'] as List<dynamic>?) ?? [];
      return LeaderboardResult(
        entries: list
            .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        playerRank: (data['player_rank'] as num?)?.toInt() ?? 0,
        playerScore: (data['player_score'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw LeaderboardException(
        e.response?.data?['error']?['message'] as String? ??
            'Failed to load leaderboard',
      );
    }
  }
}
