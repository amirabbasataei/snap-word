import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/network/api_endpoints.dart';

class PowerupUseResult {
  final int remaining; // inventory left for the type
  final int coinsSpent; // 0 when the use came out of inventory
  final int? coins; // balance after the use

  const PowerupUseResult({
    required this.remaining,
    required this.coinsSpent,
    this.coins,
  });
}

class PowerupUnavailableException implements Exception {}

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
  }) : _db = db,
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
  ) => _db.transaction(() async {
    await _matchDao.finishMatch(
      localMatchId,
      score,
      wordChain.length,
      jsonEncode(wordChain),
    );
    await _usedWordDao.deleteWordsForMatch(localMatchId);
  });

  /// Owned inventory per power-up type, as last synced from the server.
  Future<Map<String, int>> getPowerupCounts() async {
    final rows = await _db.powerupCacheDao.getAll();
    return {for (final r in rows) r.powerupType: r.quantity};
  }

  /// Credits the rewarded-ad bonus server-side; returns the new coin balance.
  Future<int> claimRewardedAd() async {
    final response = await _dio.post(ApiEndpoints.rewardedAdClaim);
    return (response.data['data'] as Map<String, dynamic>)['coins'] as int;
  }

  /// Consumes one use server-side (inventory first, coins as fallback) and
  /// mirrors the new inventory into the local cache. Throws
  /// [PowerupUnavailableException] when the player has neither.
  Future<PowerupUseResult> usePowerup(String type) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.powerupUse,
        data: {'powerup_type': type},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final result = PowerupUseResult(
        remaining: data['quantity_remaining'] as int? ?? 0,
        coinsSpent: data['coins_spent'] as int? ?? 0,
        coins: data['coins'] as int?,
      );
      await _db.powerupCacheDao.setQuantity(type, result.remaining);
      return result;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) throw PowerupUnavailableException();
      rethrow;
    }
  }
}
