import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';
part 'daos/match_dao.dart';
part 'daos/used_word_dao.dart';
part 'daos/stats_dao.dart';
part 'daos/powerup_cache_dao.dart';

class LocalMatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get mode => text()();
  TextColumn get opponentType => text()();
  TextColumn get status => text()();
  IntColumn get score => integer().withDefault(const Constant(0))();
  IntColumn get chainLength => integer().withDefault(const Constant(0))();
  TextColumn get wordChain =>
      text().withDefault(const Constant('[]'))();
  BoolColumn get synced =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
}

class LocalUsedWords extends Table {
  IntColumn get matchId => integer()();
  TextColumn get word => text()();

  @override
  Set<Column> get primaryKey => {matchId, word};
}

class LocalPlayerStats extends Table {
  IntColumn get id =>
      integer().withDefault(const Constant(1))();
  IntColumn get totalMatches =>
      integer().withDefault(const Constant(0))();
  IntColumn get wins =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestScore =>
      integer().withDefault(const Constant(0))();
  IntColumn get bestMatchStreak =>
      integer().withDefault(const Constant(0))();
  IntColumn get dailyStreak =>
      integer().withDefault(const Constant(0))();
  IntColumn get longestDailyStreak =>
      integer().withDefault(const Constant(0))();
  TextColumn get longestWord => text().nullable()();
  DateTimeColumn get lastPlayedDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LocalPowerupCacheEntry')
class LocalPowerupCache extends Table {
  TextColumn get powerupType => text()();
  IntColumn get quantity =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {powerupType};
}

@DriftDatabase(
  tables: [
    LocalMatches,
    LocalUsedWords,
    LocalPlayerStats,
    LocalPowerupCache,
  ],
  daos: [MatchDao, UsedWordDao, StatsDao, PowerupCacheDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openDatabase());

  static QueryExecutor _openDatabase() {
    return driftDatabase(name: 'wordchain.db');
  }

  @override
  int get schemaVersion => 1;
}
