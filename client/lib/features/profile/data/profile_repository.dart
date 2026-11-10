import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/utils/error_messages.dart';
import 'package:wordchain/features/game/data/game_constants.dart';

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
  final int level;
  final int xpInLevel;
  final int xpForNext;

  /// «جام» (Elo, starts at 1000), its peak, the games that moved it, and the
  /// lifetime 1v1 word points (no longer shown in the app). Signed-in players only.
  final int rating;
  final int ratedGames;
  final int peakRating;
  final int totalScore;

  const ProfileStats({
    required this.totalMatches,
    required this.wins,
    required this.bestScore,
    required this.bestMatchStreak,
    required this.dailyStreak,
    required this.longestDailyStreak,
    this.longestWord,
    required this.coins,
    this.level = 1,
    this.xpInLevel = 0,
    this.xpForNext = 1000,
    this.rating = GameConstants.ratingStart,
    this.ratedGames = 0,
    this.peakRating = GameConstants.ratingStart,
    this.totalScore = 0,
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
    level: json['level'] as int? ?? 1,
    xpInLevel: json['xp_in_level'] as int? ?? 0,
    xpForNext: json['xp_for_next'] as int? ?? 1000,
    rating: json['rating'] as int? ?? GameConstants.ratingStart,
    ratedGames: json['rated_games'] as int? ?? 0,
    peakRating: json['peak_rating'] as int? ?? GameConstants.ratingStart,
    totalScore: json['total_score'] as int? ?? 0,
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
    level: level,
    xpInLevel: xpInLevel,
    xpForNext: xpForNext,
    rating: rating,
    ratedGames: ratedGames,
    peakRating: peakRating,
    totalScore: totalScore,
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

/// Premium subscription state + chosen avatar (`GET /profile/perks`).
class PremiumPerks {
  final bool isPremium;
  final DateTime? premiumUntil;
  final String? avatarId;

  const PremiumPerks({
    required this.isPremium,
    this.premiumUntil,
    this.avatarId,
  });

  static const none = PremiumPerks(isPremium: false);

  factory PremiumPerks.fromJson(Map<String, dynamic> json) {
    final avatar = json['avatar_id'] as String?;
    final until = json['premium_until'] as String?;
    return PremiumPerks(
      isPremium: json['is_premium'] as bool? ?? false,
      premiumUntil: until == null ? null : DateTime.tryParse(until),
      avatarId: (avatar == null || avatar.isEmpty) ? null : avatar,
    );
  }

  PremiumPerks withAvatar(String id) => PremiumPerks(
    isPremium: isPremium,
    premiumUntil: premiumUntil,
    avatarId: id,
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
        apiErrorMessage(e, fallback: loadProfileFailedMessage),
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
        apiErrorMessage(e, fallback: loadInventoryFailedMessage),
      );
    }
  }

  Future<PremiumPerks> fetchPerks() async {
    try {
      final response = await _dio.get(ApiEndpoints.profilePerks);
      return PremiumPerks.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ProfileException(
        apiErrorMessage(e, fallback: loadProfileFailedMessage),
      );
    }
  }

  Future<void> setAvatar(String avatarId) async {
    try {
      await _dio.patch(
        ApiEndpoints.profileAvatar,
        data: {'avatar_id': avatarId},
      );
    } on DioException catch (e) {
      throw ProfileException(apiErrorMessage(e));
    }
  }
}
