part of '../app_database.dart';

@DriftAccessor(tables: [LocalMatches])
class MatchDao extends DatabaseAccessor<AppDatabase> with _$MatchDaoMixin {
  MatchDao(super.db);

  Future<int> createMatch(LocalMatchesCompanion match) =>
      into(localMatches).insert(match);

  Future<bool> updateMatch(LocalMatchesCompanion match) =>
      update(localMatches).replace(match);

  Future<LocalMatche?> getActiveMatch() => (select(localMatches)
        ..where((t) => t.status.equals('active'))
        ..limit(1))
      .getSingleOrNull();

  Future<List<LocalMatche>> getUnsyncedMatches() =>
      (select(localMatches)
            ..where((t) => t.synced.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
          .get();

  Future<void> markSynced(int id, String remoteId) =>
      (update(localMatches)..where((t) => t.id.equals(id))).write(
        LocalMatchesCompanion(
          synced: const Value(true),
          remoteId: Value(remoteId),
        ),
      );
}
