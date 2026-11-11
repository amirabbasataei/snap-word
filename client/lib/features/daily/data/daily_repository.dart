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

  /// The variant this is about: the letter position that links words (1
  /// classic, 2/3 the harder ones, `GameConstants.dailyVariants`). Each is its
  /// own daily: attempt, retry, board and prizes.
  final int variant;

  /// The variant's turn timer (server-sent; the app mirrors it in
  /// `GameConstants.dailyTurnTimerSec`).
  final int turnTimerSec;

  /// Variants the player has a free attempt at today (the type picker
  /// marks them). Empty from a server older than the variants.
  final List<int> playedVariants;

  /// The letter the first word carries at position [variant].
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
    this.variant = 1,
    this.turnTimerSec = 15,
    this.playedVariants = const [],
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

  /// The player's best attempt, shown as their result: the paid retry replaces
  /// the first attempt only when it scored higher (a tie keeps the first). The
  /// server's rank and prizes come from the free attempt alone, whichever of
  /// the two this is.
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
    variant: json['variant'] as int? ?? 1,
    turnTimerSec: json['turn_timer_sec'] as int? ?? 15,
    playedVariants:
        (json['played_variants'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [],
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

  /// Today's challenge of [variant] (1 = classic).
  Future<DailyChallenge> getDailyChallenge({int variant = 1}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.daily,
        queryParameters: {'variant': variant},
      );
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

  /// Buys the paid second attempt at [variant].
  Future<void> retryChallenge({int variant = 1}) async {
    try {
      await _dio.post(
        ApiEndpoints.dailyRetry,
        queryParameters: {'variant': variant},
      );
    } on DioException catch (e) {
      throw DailyException(
        code: apiErrorCode(e),
        message: apiErrorMessage(e, fallback: dailyRetryFailedMessage),
      );
    }
  }
}
