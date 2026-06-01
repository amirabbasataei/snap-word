import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class GameRepository {
  final AppDatabase _db;
  final MatchDao _matchDao;
  final UsedWordDao _usedWordDao;
  final Dio _dio;

  GameRepository({
    required AppDatabase db,
    required MatchDao matchDao,
    required UsedWordDao usedWordDao,
    required Dio dio,
  })  : _db = db,
        _matchDao = matchDao,
        _usedWordDao = usedWordDao,
        _dio = dio;

  Future<int> startLocalGame(String mode, String opponentType) =>
      _matchDao.createMatch(
        LocalMatchesCompanion(
          mode: Value(mode),
          opponentType: Value(opponentType),
          status: const Value('active'),
          startedAt: Value(DateTime.now()),
        ),
      );

  Future<LocalMatche?> getActiveMatch() => _matchDao.getActiveMatch();

  Future<LocalMatche?> getMatchById(int id) => _matchDao.getMatchById(id);

  Future<bool> isWordUsed(int matchId, String word) =>
      _usedWordDao.isWordUsed(matchId, word);

  // Atomically inserts the word into used_words and updates the chain JSON.
  Future<void> recordAcceptedWord(int matchId, List<String> updatedChain) =>
      _db.transaction(() async {
        await _usedWordDao.insertWord(matchId, updatedChain.last);
        await _matchDao.updateWordChainForMatch(matchId, updatedChain);
      });

  Future<void> finishLocalGame(
    int localMatchId,
    int score,
    List<String> wordChain,
  ) =>
      _db.transaction(() async {
        await _matchDao.finishMatch(
          localMatchId,
          score,
          wordChain.length,
          jsonEncode(wordChain),
        );
        await _usedWordDao.deleteWordsForMatch(localMatchId);
      });

  Future<void> usePowerup(String type) =>
      _dio.post(ApiEndpoints.powerupUse, data: {'type': type});
}
