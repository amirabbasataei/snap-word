import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class ProfileException implements Exception {
  final String message;
  const ProfileException(this.message);
}

class ProfileStats {
  final int totalMatches;
  final int wins;
  final int bestScore;
  final int bestMatchStreak;
  final int dailyStreak;
  final int longestDailyStreak;
  final String? longestWord;
  final int coins;

  const ProfileStats({
    required this.totalMatches,
    required this.wins,
    required this.bestScore,
    required this.bestMatchStreak,
    required this.dailyStreak,
    required this.longestDailyStreak,
    this.longestWord,
    required this.coins,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) => ProfileStats(
        totalMatches: json['total_matches'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        bestScore: json['best_score'] as int? ?? 0,
        bestMatchStreak: json['best_match_streak'] as int? ?? 0,
        dailyStreak: json['daily_streak'] as int? ?? 0,
        longestDailyStreak: json['longest_daily_streak'] as int? ?? 0,
        longestWord: json['longest_word'] as String?,
        coins: json['coins'] as int? ?? 0,
      );

  ProfileStats copyWith({int? coins}) => ProfileStats(
        totalMatches: totalMatches,
        wins: wins,
        bestScore: bestScore,
        bestMatchStreak: bestMatchStreak,
        dailyStreak: dailyStreak,
        longestDailyStreak: longestDailyStreak,
        longestWord: longestWord,
        coins: coins ?? this.coins,
      );
}

class PowerupItem {
  final String type;
  final int quantity;

  const PowerupItem({required this.type, required this.quantity});

  factory PowerupItem.fromJson(Map<String, dynamic> json) => PowerupItem(
        type: json['powerup_type'] as String,
        quantity: json['quantity'] as int? ?? 0,
      );
}

class ProfileRepository {
  final Dio _dio;

  ProfileRepository({required Dio dio}) : _dio = dio;

  Future<ProfileStats> fetchStats() async {
    try {
      final response = await _dio.get(ApiEndpoints.profileStats);
      return ProfileStats.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ProfileException(
        e.response?.data?['error']?['message'] as String? ??
            'Failed to load profile',
      );
    }
  }

  Future<List<PowerupItem>> fetchInventory() async {
    try {
      final response = await _dio.get(ApiEndpoints.powerupInventory);
      final data = response.data['data'] as Map<String, dynamic>?;
      final list = (data?['items'] as List<dynamic>?) ?? [];
      return list
          .map((e) => PowerupItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ProfileException(
        e.response?.data?['error']?['message'] as String? ??
            'Failed to load inventory',
      );
    }
  }
}
