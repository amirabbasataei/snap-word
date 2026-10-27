import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

class _FakeRepo extends Fake implements GameRepository {
  @override
  Future<int> startLocalGame(String mode, String opponentType) async => 1;

  @override
  Future<void> finishLocalGame(
    int localMatchId,
    int score,
    List<String> wordChain,
  ) async {}
}

class _FakeDictionary extends Fake implements DictionaryService {}

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

class _FakeWs extends WebSocketService {
  final _events = StreamController<WebSocketEvent>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<WebSocketEvent> get events => _events.stream;

  @override
  void connect(String url) {}

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  void disconnect() {}

  void emit(String type, Map<String, dynamic> data) =>
      _events.add(WebSocketEvent(type, {'type': type, ...data}));
}

const _me = 'me-id';
const _them = 'them-id';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _FakeWs ws;
  late GameBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ws = _FakeWs();
    bloc = GameBloc(
      gameRepository: _FakeRepo(),
      dictionaryService: _FakeDictionary(),
      statsDao: _FakeStatsDao(),
      syncService: _FakeSync(),
      prefs: await SharedPreferences.getInstance(),
      wsService: ws,
    );
    bloc.add(
      const GameStarted(
        mode: 'classic',
        opponentType: 'multiplayer',
        roomId: 'room-1',
        myPlayerId: _me,
      ),
    );
    await _settle();
    ws.emit('game_start', {
      'state': {
        'players': [_me, _them],
        'mode': 'classic',
        'current_turn': _me,
      },
    });
    await _settle();
  });

  tearDown(() => bloc.close());

  test('my refused word reaches the result screen (so it can be reported)', () async {
    ws.emit('word_rejected', {
      'word': 'قلمم',
      'reason': 'not_in_dictionary',
      'player_id': _me,
    });
    ws.emit('loss_event', {'player_id': _me, 'reason': 'invalid_word'});
    await _settle();

    final over = bloc.state as GameOver;
    expect(over.rejectedWord, 'قلمم');
    expect(over.rejectionReason, 'not_in_dictionary');
  });

  test('the word survives the server game_over that follows a declined continue', () async {
    ws.emit('word_rejected', {
      'word': 'قلمم',
      'reason': 'not_in_dictionary',
      'player_id': _me,
    });
    ws.emit('loss_event', {'player_id': _me, 'reason': 'invalid_word'});
    await _settle();
    ws.emit('game_over', {
      'winner': _them,
      'scores': {_me: 0, _them: 0},
    });
    await _settle();

    final over = bloc.state as GameOver;
    expect(over.reason, 'game_over');
    expect(over.rejectedWord, 'قلمم');
    expect(over.iWon, isFalse);
  });

  test('the opponent\'s refused word is not mine to report', () async {
    ws.emit('word_rejected', {
      'word': 'قلمم',
      'reason': 'not_in_dictionary',
      'player_id': _them,
    });
    ws.emit('loss_event', {'player_id': _them, 'reason': 'invalid_word'});
    await _settle();
    ws.emit('game_over', {
      'winner': _me,
      'scores': {_me: 10, _them: 0},
    });
    await _settle();

    final over = bloc.state as GameOver;
    expect(over.iWon, isTrue);
    expect(over.rejectedWord, isNull);
  });

  test('a timeout loss carries no refused word', () async {
    ws.emit('loss_event', {'player_id': _me, 'reason': 'timeout'});
    await _settle();
    expect((bloc.state as GameOver).rejectedWord, isNull);
  });
}
