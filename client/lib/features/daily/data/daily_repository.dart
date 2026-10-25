import 'package:dio/dio.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/utils/error_messages.dart';

class DailyException implements Exception {
  final String code;
  final String message;
  const DailyException({required this.code, required this.message});
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
    wordChain:
        (json['word_chain'] as List<dynamic>?)
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

  /// One free attempt, then one paid retry (`POST /daily/retry`).
  bool get canRetry => hasAttempted && !hasRetried;

  /// The attempt that counts: the server ranks the player by their best score,
  /// so the paid retry only replaces the first attempt when it scored higher
  /// (a tie keeps the first).
  DailyAttempt? get bestAttempt {
    final first = attempt;
    final retry = retryAttempt;
    if (first == null) return retry;
    if (retry == null) return first;
    return retry.score > first.score ? retry : first;
  }

  factory DailyChallenge.fromJson(Map<String, dynamic> json) => DailyChallenge(
    challengeDate: json['challenge_date'] as String? ?? '',
    dayNumber: json['day_number'] as int? ?? 1,
    startLetter: (json['start_letter'] as String? ?? 'a').toLowerCase(),
    todaysBest: json['today_best'] as int? ?? 0,
    yourBest: json['your_best'] as int? ?? 0,
    dailyStreak: json['daily_streak'] as int? ?? 0,
    attempt:
        json['attempt'] != null
            ? DailyAttempt.fromJson(json['attempt'] as Map<String, dynamic>)
            : null,
    retryAttempt:
        json['retry_attempt'] != null
            ? DailyAttempt.fromJson(
              json['retry_attempt'] as Map<String, dynamic>,
            )
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
        code: apiErrorCode(e),
        message: apiErrorMessage(e, fallback: loadDailyFailedMessage),
      );
    }
  }

  Future<void> retryChallenge() async {
    try {
      await _dio.post(ApiEndpoints.dailyRetry);
    } on DioException catch (e) {
      throw DailyException(
        code: apiErrorCode(e),
        message: apiErrorMessage(e, fallback: dailyRetryFailedMessage),
      );
    }
  }
}
