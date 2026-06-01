part of '../app_database.dart';

@DriftAccessor(tables: [LocalUsedWords])
class UsedWordDao extends DatabaseAccessor<AppDatabase>
    with _$UsedWordDaoMixin {
  UsedWordDao(super.db);

  Future<void> insertWord(int matchId, String word) =>
      into(localUsedWords).insert(
        LocalUsedWordsCompanion(
          matchId: Value(matchId),
          word: Value(word),
        ),
      );

  Future<bool> isWordUsed(int matchId, String word) async {
    final row = await (select(localUsedWords)
          ..where(
            (t) => t.matchId.equals(matchId) & t.word.equals(word),
          ))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> deleteWordsForMatch(int matchId) =>
      (delete(localUsedWords)..where((t) => t.matchId.equals(matchId)))
          .go();
}
