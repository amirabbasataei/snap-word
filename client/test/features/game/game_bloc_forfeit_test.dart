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
  });

  tearDown(() => bloc.close());

  Future<void> startMultiplayer() async {
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
    expect(bloc.state, isA<GameActive>());
  }

  List<Map<String, dynamic>> forfeits() =>
      ws.sent.where((m) => m['type'] == 'forfeit').toList();

  test('exit in multiplayer sends forfeit once and shows a loss', () async {
    await startMultiplayer();

    bloc.add(const GameEnded());
    bloc.add(const GameEnded()); // a double tap must not resend
    await _settle();

    expect(forfeits(), hasLength(1));
    final over = bloc.state as GameOver;
    expect(over.iWon, isFalse);
    expect(over.reason, 'ended_by_user');
  });

  test('exit after the server game_over sends nothing', () async {
    await startMultiplayer();
    ws.emit('game_over', {
      'winner': _them,
      'scores': {_me: 0, _them: 0},
    });
    await _settle();
    expect(bloc.state, isA<GameOver>());

    bloc.add(const GameEnded());
    await _settle();

    expect(forfeits(), isEmpty);
    expect((bloc.state as GameOver).winnerId, _them);
  });

  for (final opponent in ['solo', 'ai_easy']) {
    test('exit in $opponent sends nothing over the socket', () async {
      bloc.add(GameStarted(mode: 'classic', opponentType: opponent));
      await _settle();
      expect(bloc.state, isA<GameActive>());

      bloc.add(const GameEnded());
      await _settle();

      expect(ws.sent, isEmpty);
      final over = bloc.state as GameOver;
      expect(over.iWon, isNull);
    });
  }
}
