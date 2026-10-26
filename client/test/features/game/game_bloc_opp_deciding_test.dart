import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

class _FakeRepo extends Fake implements GameRepository {}

class _FakeDictionary extends Fake implements DictionaryService {}

class _FakeStatsDao extends Fake implements StatsDao {}

class _FakeSync extends Fake implements SyncService {}

class _FakeWs extends WebSocketService {
  final _events = StreamController<WebSocketEvent>.broadcast();

  @override
  Stream<WebSocketEvent> get events => _events.stream;

  @override
  void connect(String url) {}

  @override
  void send(Map<String, dynamic> message) {}

  @override
  void disconnect() {}

  void emit(String type, Map<String, dynamic> data) =>
      _events.add(WebSocketEvent(type, {'type': type, ...data}));
}

const _me = 'me-id';
const _them = 'them-id';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// The "opponent deciding" window (canvas `ZOppDeciding`) as the bloc drives it.
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
        'current_turn': _them,
      },
    });
    await _settle();
  });

  tearDown(() => bloc.close());

  GameActive active() => bloc.state as GameActive;

  test('the opponent losing opens the window with the real length and '
      'reason', () async {
    ws.emit('loss_event', {'player_id': _them, 'reason': 'timeout'});
    await _settle();
    expect(active().opponentContinueWindowActive, isTrue);
    expect(
      active().opponentContinueWindowRemaining,
      GameConstants.continueWindowSec,
    );
    expect(active().opponentLossReason, 'timeout');
  });

  test('a missing reason falls back to a rejected word', () async {
    ws.emit('loss_event', {'player_id': _them});
    await _settle();
    expect(active().opponentLossReason, 'invalid_word');
  });

  test('each tick counts the window down and the last one closes it', () async {
    ws.emit('loss_event', {'player_id': _them, 'reason': 'invalid_word'});
    await _settle();
    bloc.add(const OpponentContinueTimerTicked());
    await _settle();
    expect(
      active().opponentContinueWindowRemaining,
      GameConstants.continueWindowSec - 1,
    );

    for (var i = 0; i < GameConstants.continueWindowSec; i++) {
      bloc.add(const OpponentContinueTimerTicked());
    }
    await _settle();
    expect(active().opponentContinueWindowActive, isFalse);
    expect(active().opponentContinueWindowRemaining, 0);
  });

  test('the opponent continuing closes the window', () async {
    ws.emit('loss_event', {'player_id': _them, 'reason': 'timeout'});
    await _settle();
    ws.emit('continue_decision', {'player_id': _them, 'decision': 'continue'});
    await _settle();
    expect(active().opponentContinueWindowActive, isFalse);
    expect(active().continueUsed, isTrue);
  });
}
