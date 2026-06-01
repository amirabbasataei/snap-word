part of '../app_database.dart';

class RemoteStats {
  final int totalMatches;
  final int wins;
  final int bestScore;
  final int bestMatchStreak;
  final int dailyStreak;
  final int longestDailyStreak;
  final String? longestWord;
  final DateTime? lastPlayedDate;

  const RemoteStats({
    required this.totalMatches,
    required this.wins,
    required this.bestScore,
    required this.bestMatchStreak,
    required this.dailyStreak,
    required this.longestDailyStreak,
    this.longestWord,
    this.lastPlayedDate,
  });

  factory RemoteStats.fromJson(Map<String, dynamic> json) => RemoteStats(
        totalMatches: json['total_matches'] as int? ?? 0,
        wins: json['wins'] as int? ?? 0,
        bestScore: json['best_score'] as int? ?? 0,
        bestMatchStreak: json['best_match_streak'] as int? ?? 0,
        dailyStreak: json['daily_streak'] as int? ?? 0,
        longestDailyStreak: json['longest_daily_streak'] as int? ?? 0,
        longestWord: json['longest_word'] as String?,
        lastPlayedDate: json['last_played_date'] != null
            ? DateTime.tryParse(json['last_played_date'] as String)
            : null,
      );
}

@DriftAccessor(tables: [LocalPlayerStats])
class StatsDao extends DatabaseAccessor<AppDatabase> with _$StatsDaoMixin {
  StatsDao(super.db);

  Future<LocalPlayerStat?> getStats() =>
      (select(localPlayerStats)..where((t) => t.id.equals(1)))
          .getSingleOrNull();

  Future<void> upsertStats(LocalPlayerStatsCompanion stats) =>
      into(localPlayerStats).insertOnConflictUpdate(stats);

  Future<void> mergeWithRemote(RemoteStats remote) async {
    final local = await getStats();

    String? bestLongestWord;
    if (local?.longestWord != null && remote.longestWord != null) {
      bestLongestWord = local!.longestWord!.length >= remote.longestWord!.length
          ? local.longestWord
          : remote.longestWord;
    } else {
      bestLongestWord = local?.longestWord ?? remote.longestWord;
    }

    await upsertStats(
      LocalPlayerStatsCompanion(
        id: const Value(1),
        totalMatches: Value(_max(local?.totalMatches ?? 0, remote.totalMatches)),
        wins: Value(_max(local?.wins ?? 0, remote.wins)),
        bestScore: Value(_max(local?.bestScore ?? 0, remote.bestScore)),
        bestMatchStreak:
            Value(_max(local?.bestMatchStreak ?? 0, remote.bestMatchStreak)),
        dailyStreak: Value(_max(local?.dailyStreak ?? 0, remote.dailyStreak)),
        longestDailyStreak: Value(
          _max(local?.longestDailyStreak ?? 0, remote.longestDailyStreak),
        ),
        longestWord: Value(bestLongestWord),
        lastPlayedDate: Value(
          _latestDate(local?.lastPlayedDate, remote.lastPlayedDate),
        ),
      ),
    );
  }

  Future<void> recordGameResult({
    required int score,
    required String? longestWord,
  }) async {
    final existing = await getStats();
    await upsertStats(
      LocalPlayerStatsCompanion(
        id: const Value(1),
        totalMatches: Value((existing?.totalMatches ?? 0) + 1),
        wins: Value(existing?.wins ?? 0),
        bestScore: Value(_max(existing?.bestScore ?? 0, score)),
        bestMatchStreak: Value(existing?.bestMatchStreak ?? 0),
        dailyStreak: Value(existing?.dailyStreak ?? 0),
        longestDailyStreak: Value(existing?.longestDailyStreak ?? 0),
        longestWord: Value(_bestWord(existing?.longestWord, longestWord)),
        lastPlayedDate: Value(DateTime.now()),
      ),
    );
  }

  int _max(int a, int b) => a > b ? a : b;

  DateTime? _latestDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  String? _bestWord(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.length >= b.length ? a : b;
  }
}
