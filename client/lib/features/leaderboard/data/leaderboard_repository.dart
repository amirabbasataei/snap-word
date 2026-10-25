import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/utils/error_messages.dart';

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

class LeaderboardException implements Exception {
  final String message;
  const LeaderboardException(this.message);
}

class LeaderboardEntry {
  final String userId;
  final String username;
  final int score;
  final int rank;
  final String? avatarId;

  /// Words in the player's chain — only the Daily Challenge board sends it.
  final int? chainLength;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.rank,
    this.avatarId,
    this.chainLength,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        score: (json['score'] as num).toInt(),
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        avatarId: _nonEmpty(json['avatar_id']),
        chainLength: (json['chain_length'] as num?)?.toInt(),
      );
}

class LeaderboardResult {
  final List<LeaderboardEntry> entries;

  /// The signed-in player's rank on this board; 0 when they have none.
  final int playerRank;

  /// The player's score, or null when the server does not say (the Daily
  /// board sends only `my_rank`, so a player below the top 100 has no score).
  final int? playerScore;
  final String? playerAvatarId;

  /// The Daily Challenge number — set on the daily board only.
  final int? dayNumber;

  const LeaderboardResult({
    required this.entries,
    required this.playerRank,
    this.playerScore,
    this.playerAvatarId,
    this.dayNumber,
  });
}

class LeaderboardRepository {
  final Dio _dio;

  LeaderboardRepository({required Dio dio}) : _dio = dio;

  /// «این هفته» — `GET /leaderboard?type=global`.
  Future<LeaderboardResult> fetchGlobal() => _fetch('global');

  /// «همیشه» — `type=alltime` (lifetime `player_stats.total_score`).
  Future<LeaderboardResult> fetchAllTime() => _fetch('alltime');

  /// «دوستان». The server's `player_rank` / `player_score` on this type are
  /// the player's rank on the *global weekly* board, so the player's place
  /// among friends is read from the entries instead (the friends board always
  /// includes the requester).
  Future<LeaderboardResult> fetchFriends(String currentUserId) async {
    final board = await _fetch('friends');
    final me = board.entries.where((e) => e.userId == currentUserId);
    return LeaderboardResult(
      entries: board.entries,
      playerRank: me.isEmpty ? 0 : me.first.rank,
      playerScore: me.isEmpty ? null : me.first.score,
      playerAvatarId: board.playerAvatarId,
    );
  }

  /// «امروز» — `GET /daily/leaderboard`, today's Daily Challenge ranking
  /// (Iran day). Entries carry `chain_length` but no avatar; the response has
  /// `my_rank` (null when the player has not played) and no score of its own,
  /// so the score comes from the player's entry when they are in the top 100.
  Future<LeaderboardResult> fetchDaily(String currentUserId) async {
    try {
      final response = await _dio.get(ApiEndpoints.dailyLeaderboard);
      final data = response.data['data'] as Map<String, dynamic>;
      final entries =
          ((data['entries'] as List<dynamic>?) ?? [])
              .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
              .toList();
      final me = entries.where((e) => e.userId == currentUserId);
      final rank = (data['my_rank'] as num?)?.toInt() ?? 0;
      return LeaderboardResult(
        entries: entries,
        playerRank: rank,
        playerScore: me.isEmpty ? null : me.first.score,
        dayNumber: (data['day_number'] as num?)?.toInt(),
      );
    } on DioException catch (e) {
      throw LeaderboardException(
        apiErrorMessage(e, fallback: loadDailyBoardFailedMessage),
      );
    }
  }

  Future<LeaderboardResult> _fetch(String type) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.leaderboard,
        queryParameters: {'type': type, 'limit': 100},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final list = (data['entries'] as List<dynamic>?) ?? [];
      return LeaderboardResult(
        entries:
            list
                .map(
                  (e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>),
                )
                .toList(),
        playerRank: (data['player_rank'] as num?)?.toInt() ?? 0,
        playerScore: (data['player_score'] as num?)?.toInt() ?? 0,
        playerAvatarId: _nonEmpty(data['player_avatar_id']),
      );
    } on DioException catch (e) {
      throw LeaderboardException(
        apiErrorMessage(e, fallback: loadLeaderboardFailedMessage),
      );
    }
  }
}
