import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:wordchain/core/services/analytics_store.dart';

part 'app_database.g.dart';
part 'daos/match_dao.dart';
part 'daos/used_word_dao.dart';
part 'daos/stats_dao.dart';
part 'daos/powerup_cache_dao.dart';
part 'daos/analytics_dao.dart';

class LocalMatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get remoteId => text().nullable()();
  TextColumn get mode => text()();
  TextColumn get opponentType => text()();
  TextColumn get status => text()();
  IntColumn get score => integer().withDefault(const Constant(0))();
  IntColumn get chainLength => integer().withDefault(const Constant(0))();
  TextColumn get wordChain => text().withDefault(const Constant('[]'))();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
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
  IntColumn get id => integer().withDefault(const Constant(1))();
  IntColumn get totalMatches => integer().withDefault(const Constant(0))();
  IntColumn get wins => integer().withDefault(const Constant(0))();
  IntColumn get bestScore => integer().withDefault(const Constant(0))();
  IntColumn get bestMatchStreak => integer().withDefault(const Constant(0))();
  IntColumn get dailyStreak => integer().withDefault(const Constant(0))();
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
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {powerupType};
}

/// Product-analytics events waiting to be uploaded (`AnalyticsService`). Rows
/// are deleted once the server acknowledges them; capped at a few thousand.
class LocalAnalyticsEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientEventId => text()();
  TextColumn get name => text()();
  IntColumn get tsMs => integer()(); // Unix milliseconds, client clock
  TextColumn get sessionId => text().nullable()();
  TextColumn get screen => text().nullable()();
  TextColumn get props => text().nullable()(); // JSON object
}

@DriftDatabase(
  tables: [
    LocalMatches,
    LocalUsedWords,
    LocalPlayerStats,
    LocalPowerupCache,
    LocalAnalyticsEvents,
  ],
  daos: [MatchDao, UsedWordDao, StatsDao, PowerupCacheDao, AnalyticsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openDatabase());

  static QueryExecutor _openDatabase() {
    return driftDatabase(name: 'wordchain.db');
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2 only adds a table; the match/stats tables are never touched.
      if (from < 2) await m.createTable(localAnalyticsEvents);
    },
  );
}
