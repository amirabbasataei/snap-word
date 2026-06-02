import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class DailyException implements Exception {
  final String message;
  const DailyException(this.message);
  @override
  String toString() => message;
}

class DailyAttempt {
  final int attemptNumber;
  final int score;
  final int chainLength;
  final List<String> wordChain;

  const DailyAttempt({
    required this.attemptNumber,
    required this.score,
    required this.chainLength,
    required this.wordChain,
  });

  factory DailyAttempt.fromJson(Map<String, dynamic> json) => DailyAttempt(
        attemptNumber: json['attempt_number'] as int? ?? 1,
        score: json['score'] as int? ?? 0,
        chainLength: json['chain_length'] as int? ?? 0,
        wordChain: (json['word_chain'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

class DailyChallenge {
  final String challengeDate;
  final int dayNumber;
  final String startLetter;
  final int todaysBest;
  final int yourBest;
  final int dailyStreak;
  final DailyAttempt? attempt;
  final DailyAttempt? retryAttempt;
  final int? rank;

  const DailyChallenge({
    required this.challengeDate,
    required this.dayNumber,
    required this.startLetter,
    required this.todaysBest,
    required this.yourBest,
    required this.dailyStreak,
    this.attempt,
    this.retryAttempt,
    this.rank,
  });

  bool get hasAttempted => attempt != null;
  bool get hasRetried => retryAttempt != null;

  factory DailyChallenge.fromJson(Map<String, dynamic> json) => DailyChallenge(
        challengeDate: json['challenge_date'] as String? ?? '',
        dayNumber: json['day_number'] as int? ?? 1,
        startLetter: (json['start_letter'] as String? ?? 'a').toLowerCase(),
        todaysBest: json['today_best'] as int? ?? 0,
        yourBest: json['your_best'] as int? ?? 0,
        dailyStreak: json['daily_streak'] as int? ?? 0,
        attempt: json['attempt'] != null
            ? DailyAttempt.fromJson(json['attempt'] as Map<String, dynamic>)
            : null,
        retryAttempt: json['retry_attempt'] != null
            ? DailyAttempt.fromJson(
                json['retry_attempt'] as Map<String, dynamic>)
            : null,
        rank: json['rank'] as int?,
      );
}

class DailyRepository {
  final Dio _dio;

  DailyRepository({required Dio dio}) : _dio = dio;

  Future<DailyChallenge> getDailyChallenge() async {
    try {
      final response = await _dio.get(ApiEndpoints.daily);
      return DailyChallenge.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw DailyException(
        e.response?.data?['error']?['message'] as String? ??
            'Failed to load daily challenge',
      );
    }
  }

  Future<void> retryChallenge() async {
    try {
      await _dio.post(ApiEndpoints.dailyRetry);
    } on DioException catch (e) {
      throw DailyException(
        e.response?.data?['error']?['message'] as String? ??
            'Not enough coins or retry already used',
      );
    }
  }
}
