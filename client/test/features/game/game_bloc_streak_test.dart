import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

class _FakeRepo extends Fake implements GameRepository {
  @override
  Future<int> startLocalGame(
    String mode,
    String opponentType, {
    int linkPosition = 1,
    String? startLetter,
  }) async => 1;

  @override
  Future<bool> isWordUsed(int localMatchId, String word) async => false;

  @override
  Future<void> recordAcceptedWord(
    int localMatchId,
    List<String> updatedChain, {
    int? responseMs,
    int? streak,
  }) async {}

  @override
  Future<void> finishLocalGame(
    int localMatchId,
    int score,
    List<String> wordChain,
  ) async {}
}

/// A chain that links: کتاب → بار → راه → هوا → اسب.
const _chain = ['کتاب', 'بار', 'راه', 'هوا', 'اسب'];

class _Dictionary extends Fake implements DictionaryService {
  @override
  bool isValid(String word) => _chain.contains(word);
}

class _FakeStatsDao extends Fake implements StatsDao {
  @override
  Future<void> recordGameResult({
    required int score,
    required String? longestWord,
    int chainLength = 0,
  }) async {}
}

class _FakeSync extends Fake implements SyncService {
  @override
  Future<void> sync() async {}
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('match streak resets on a mistake (lives modes)', () {
    late GameBloc bloc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      bloc = GameBloc(
        gameRepository: _FakeRepo(),
        dictionaryService: _Dictionary(),
        statsDao: _FakeStatsDao(),
        syncService: _FakeSync(),
        prefs: await SharedPreferences.getInstance(),
        wsService: WebSocketService(),
      )..add(const GameStarted(mode: 'classic', opponentType: 'solo'));
      await _settle();
      for (final w in _chain.take(3)) {
        bloc.add(WordSubmitted(w));
        await _settle();
      }
      expect((bloc.state as GameActive).streak, 3);
    });

    tearDown(() => bloc.close());

    test('an invalid word that costs a life resets the streak', () async {
      bloc.add(const WordSubmitted('هلو')); // not in the fake dictionary
      await _settle();

      var active = bloc.state as GameActive;
      expect(active.livesRemaining, GameConstants.soloLives - 1);
      expect(active.streak, 0);

      bloc.add(WordSubmitted(_chain[3]));
      await _settle();
      active = bloc.state as GameActive;
      expect(active.streak, 1);
      // Streak was 0 before this word: at most the instant score without the
      // +50 % bonus.
      final noBonus = GameBloc.calculateScore(
        _chain[3],
        0,
        0,
        GameConstants.classicTurnTimerSec.toDouble(),
      );
      expect(active.wordScores.last, lessThanOrEqualTo(noBonus));
    });

    test('a timeout that costs a life resets the streak', () async {
      for (var i = 0; i < GameConstants.classicTurnTimerSec; i++) {
        bloc.add(const GameTimerTicked());
      }
      await _settle();

      final active = bloc.state as GameActive;
      expect(active.livesRemaining, GameConstants.soloLives - 1);
      expect(active.lastMistakeReason, 'timeout');
      expect(active.streak, 0);
    });
  });

  group('scorer', () {
    const limit = 15.0;

    test('the half-space is not a letter', () {
      expect(GameBloc.letterCount('آب‌بازی'), 6);
      expect(GameBloc.letterCount('کتاب'), 4);
      // 6 letters + ZWNJ: base 60, no long-word bonus.
      expect(GameBloc.calculateScore('آب‌بازی', limit, 0, limit), 60);
    });

    test('the long-word bonus counts letters only', () {
      // 8 letters, no half-space → base 80 + 2 × 15.
      expect(GameBloc.calculateScore('کتابخانه', limit, 0, limit), 80 + 30);
    });

    test('the streak bonus needs three words before this one', () {
      expect(GameBloc.calculateScore('کتاب', limit, 2, limit), 40);
      expect(GameBloc.calculateScore('کتاب', limit, 3, limit), 60);
    });
  });
}
