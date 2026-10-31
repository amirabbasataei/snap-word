import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/bloc/game_event.dart';
import 'package:wordchain/features/game/bloc/game_state.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

class _FakeRepo extends Fake implements GameRepository {
  @override
  Future<int> startLocalGame(String mode, String opponentType) async => 1;

  @override
  Future<bool> isWordUsed(int localMatchId, String word) async => false;

  @override
  Future<void> recordAcceptedWord(
    int localMatchId,
    List<String> updatedChain,
  ) async {}

  @override
  Future<void> finishLocalGame(
    int localMatchId,
    int score,
    List<String> wordChain,
  ) async {}
}

/// Knows exactly one word.
class _Dictionary extends Fake implements DictionaryService {
  @override
  bool isValid(String word) => word == 'کتاب';
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
    )..add(const GameStarted(mode: 'daily', opponentType: 'solo'));
    await _settle();
  });

  tearDown(() => bloc.close());

  test(
    'a refused word that costs a life is kept for the report toast',
    () async {
      expect(
        (bloc.state as GameActive).livesRemaining,
        GameConstants.soloLives,
      );

      bloc.add(const WordSubmitted('قلمم'));
      await _settle();

      final active = bloc.state as GameActive;
      expect(active.livesRemaining, GameConstants.soloLives - 1);
      expect(active.lastMistakeReason, 'not_in_dictionary');
      expect(active.lastMistakeWord, 'قلمم');
    },
  );

  test('a valid word clears the remembered mistake', () async {
    bloc.add(const WordSubmitted('قلمم'));
    await _settle();
    bloc.add(const WordSubmitted('کتاب'));
    await _settle();

    final active = bloc.state as GameActive;
    expect(active.lastMistakeReason, isNull);
    expect(active.lastMistakeWord, isNull);
  });

  test('the last life ends the game with the word on the result', () async {
    for (var i = 0; i < GameConstants.soloLives; i++) {
      bloc.add(const WordSubmitted('قلمم'));
      await _settle();
    }

    final over = bloc.state as GameOver;
    expect(over.rejectionReason, 'not_in_dictionary');
    expect(over.rejectedWord, 'قلمم');
  });
}
