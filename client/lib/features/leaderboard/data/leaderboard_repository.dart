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

  /// Rated games behind the row (this week on the weekly board, in total on
  /// the all-time and friends boards); null on the Daily board.
  final int? games;

  /// Wins this week — the weekly board only.
  final int? wins;

  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.score,
    required this.rank,
    this.avatarId,
    this.chainLength,
    this.games,
    this.wins,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        score: (json['score'] as num).toInt(),
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        avatarId: _nonEmpty(json['avatar_id']),
        chainLength: (json['chain_length'] as num?)?.toInt(),
        games: (json['games'] as num?)?.toInt(),
        wins: (json['wins'] as num?)?.toInt(),
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

  /// The player's rated games on this board (`player_games`) and, on the
  /// weekly board, their wins this week (`player_wins`); null when the server
  /// does not say (Daily).
  final int? playerGames;
  final int? playerWins;

  /// The Daily Challenge number — set on the daily board only.
  final int? dayNumber;

  const LeaderboardResult({
    required this.entries,
    required this.playerRank,
    this.playerScore,
    this.playerAvatarId,
    this.playerGames,
    this.playerWins,
    this.dayNumber,
  });
}

class LeaderboardRepository {
  final Dio _dio;

  LeaderboardRepository({required Dio dio}) : _dio = dio;

  /// «این هفته» — `GET /leaderboard?type=global`: the week's net «جام»
  /// (`score`, can be negative), wins and rated games.
  Future<LeaderboardResult> fetchGlobal() => _fetch('global');

  /// «همیشه» — `type=alltime`: the rating, only for players with at least ten
  /// rated games (`player_rank` 0 = not ranked yet, `player_score` is still
  /// the rating).
  Future<LeaderboardResult> fetchAllTime() => _fetch('alltime');

  /// «دوستان» — `type=friends`: the player and their accepted friends by
  /// rating; `player_rank` is the place among friends.
  Future<LeaderboardResult> fetchFriends() => _fetch('friends');

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
        playerGames: (data['player_games'] as num?)?.toInt(),
        playerWins: (data['player_wins'] as num?)?.toInt(),
      );
    } on DioException catch (e) {
      throw LeaderboardException(
        apiErrorMessage(e, fallback: loadLeaderboardFailedMessage),
      );
    }
  }
}
