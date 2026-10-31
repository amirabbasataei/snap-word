import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/share_service.dart';
import 'package:wordchain/features/daily/data/daily_repository.dart';

/// Nineteen words, enough for the «N کلمهٔ دیگر» chip (the links between them
/// do not matter to the screen).
const dailyWords = [
  'بادام',
  'مداد',
  'داریوش',
  'شاهنامه',
  'هوا',
  'انار',
  'رودخانه',
  'هلو',
  'واژه',
  'هوشمند',
  'دریا',
  'ایران',
  'نارنج',
  'جاده',
  'هنر',
  'رنگ',
  'گلاب',
  'بهار',
  'رود',
];

DailyAttempt dailyAttempt({
  int number = 1,
  int score = 460,
  List<String> words = dailyWords,
}) => DailyAttempt(
  attemptNumber: number,
  score: score,
  chainLength: words.length,
  wordChain: words,
);

/// 2026-10-16 is «جمعه ۲۴ مهر».
DailyChallenge dailyChallenge({
  bool played = false,
  DailyAttempt? attempt,
  DailyAttempt? retry,
  int streak = 7,
  int best = 460,
  int? rank = 3,
  String date = '2026-10-16',
  String letter = 'ب',
}) => DailyChallenge(
  challengeDate: date,
  dayNumber: 42,
  startLetter: letter,
  todaysBest: best,
  yourBest: attempt?.score ?? 0,
  dailyStreak: streak,
  attempt: attempt ?? (played ? dailyAttempt() : null),
  retryAttempt: retry,
  rank: rank,
);

class FakeDailyRepo extends Fake implements DailyRepository {
  DailyChallenge challenge;
  Object? loadError;
  Object? retryError;
  Completer<DailyChallenge>? loadGate;
  Completer<void>? retryGate;
  int loads = 0;
  int retries = 0;

  FakeDailyRepo(this.challenge);

  @override
  Future<DailyChallenge> getDailyChallenge() async {
    loads++;
    final gate = loadGate;
    if (gate != null) return gate.future;
    final error = loadError;
    if (error != null) throw error;
    return challenge;
  }

  @override
  Future<void> retryChallenge() async {
    retries++;
    final gate = retryGate;
    if (gate != null) await gate.future;
    final error = retryError;
    if (error != null) throw error;
  }
}

class FakeShare extends Fake implements ShareService {
  final shared = <DailyChallengeResult>[];

  @override
  Future<void> shareDaily(
    BuildContext context,
    DailyChallengeResult result,
  ) async =>
      shared.add(result);
}

class FakeStats extends Fake implements StatsDao {
  final LocalPlayerStat? stats;

  FakeStats({DateTime? lastPlayed, int record = 12, bool none = false})
    : stats =
          none
              ? null
              : LocalPlayerStat(
                id: 1,
                totalMatches: 0,
                wins: 0,
                bestScore: 0,
                bestMatchStreak: 0,
                dailyStreak: 0,
                longestDailyStreak: record,
                lastPlayedDate: lastPlayed,
              );

  @override
  Future<LocalPlayerStat?> getStats() async => stats;
}
