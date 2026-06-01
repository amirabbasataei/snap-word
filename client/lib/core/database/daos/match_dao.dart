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

  Future<LocalMatche?> getMatchById(int id) =>
      (select(localMatches)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> updateWordChainForMatch(int id, List<String> chain) =>
      (update(localMatches)..where((t) => t.id.equals(id))).write(
        LocalMatchesCompanion(
          chainLength: Value(chain.length),
          wordChain: Value(jsonEncode(chain)),
        ),
      );

  Future<void> finishMatch(
    int id,
    int score,
    int chainLength,
    String wordChainJson,
  ) =>
      (update(localMatches)..where((t) => t.id.equals(id))).write(
        LocalMatchesCompanion(
          status: const Value('finished'),
          score: Value(score),
          chainLength: Value(chainLength),
          wordChain: Value(wordChainJson),
          endedAt: Value(DateTime.now()),
        ),
      );
}
