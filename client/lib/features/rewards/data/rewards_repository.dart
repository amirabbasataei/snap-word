import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class RewardsException implements Exception {
  final String code;
  const RewardsException(this.code);
}

/// A claimable coin prize.
class RewardItem {
  final String id;
  final String kind; // referral_reward | streak | weekly_rank | daily_login | daily_rank | daily_done
  final String detail; // friend's username / streak days / rank
  final int coins;
  final bool claimed;
  final DateTime createdAt;

  const RewardItem({
    required this.id,
    required this.kind,
    required this.detail,
    required this.coins,
    required this.claimed,
    required this.createdAt,
  });

  factory RewardItem.fromJson(Map<String, dynamic> json) => RewardItem(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        coins: json['coins'] as int? ?? 0,
        claimed: json['claimed'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  RewardItem asClaimed() => RewardItem(
        id: id,
        kind: kind,
        detail: detail,
        coins: coins,
        claimed: true,
        createdAt: createdAt,
      );
}

class RewardsSnapshot {
  final List<RewardItem> items;
  final int coins; // live server balance

  const RewardsSnapshot({required this.items, required this.coins});
}

class RewardsRepository {
  final Dio _dio;

  RewardsRepository({required Dio dio}) : _dio = dio;

  Future<RewardsSnapshot> fetch() async {
    try {
      final response = await _dio.get(ApiEndpoints.rewards);
      final data = response.data['data'] as Map<String, dynamic>;
      return RewardsSnapshot(
        items: (data['items'] as List<dynamic>)
            .map((e) => RewardItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        coins: data['coins'] as int? ?? 0,
      );
    } on DioException catch (e) {
      throw RewardsException(e.response?.data?['error']?['code'] as String? ?? 'network');
    }
  }

  /// Returns the coins credited.
  Future<int> claim(String id) async {
    try {
      final response = await _dio.post(ApiEndpoints.rewardClaim(id));
      return (response.data['data'] as Map<String, dynamic>)['coins_awarded'] as int;
    } on DioException catch (e) {
      throw RewardsException(e.response?.data?['error']?['code'] as String? ?? 'network');
    }
  }
}
