import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_repository.dart';

class _FakeRepo extends Fake implements GameRepository {}

class _FakeDictionary extends Fake implements DictionaryService {}

class _FakeStatsDao extends Fake implements StatsDao {}

class _FakeSync extends Fake implements SyncService {}

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
    SharedPreferences.setMockInitialValues(
      {},
    ); // no JWT → guest, no inventory fetch
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
  });

  tearDown(() => bloc.close());

  Future<GameActive> startGame({
    List<String> premium = const [],
    Map<String, String> avatars = const {},
  }) async {
    ws.emit('game_start', {
      'state': {
        'players': [_me, _them],
        'mode': 'classic',
        'current_turn': _me,
        'premium': premium,
        'avatars': avatars,
      },
    });
    await _settle();
    return bloc.state as GameActive;
  }

  test(
    'game_start carries premium flags and avatars for both players',
    () async {
      final s = await startGame(premium: [_me], avatars: {_me: 'lion'});
      expect(s.myPremium, isTrue);
      expect(s.opponentPremium, isFalse);
      expect(s.myAvatarId, 'lion');
      expect(s.opponentAvatarId, isNull);
    },
  );

  test('game_start without perk fields (old server) means no perks', () async {
    ws.emit('game_start', {
      'state': {
        'players': [_me, _them],
        'current_turn': _me,
      },
    });
    await _settle();
    final s = bloc.state as GameActive;
    expect(s.myPremium, isFalse);
    expect(s.opponentPremium, isFalse);
  });

  test(
    'an incoming taunt is recorded with its owner and bumps the seq',
    () async {
      await startGame();
      ws.emit('taunt', {
        'player_id': _them,
        'taunt': 'hurry_up',
        'text': 'زود باش!',
      });
      await _settle();
      var s = bloc.state as GameActive;
      expect(s.tauntId, 'hurry_up');
      expect(s.tauntText, 'زود باش!');
      expect(s.tauntFromMe, isFalse);
      final firstSeq = s.tauntSeq;

      ws.emit('taunt', {
        'player_id': _me,
        'taunt': 'hurry_up',
        'text': 'زود باش!',
      });
      await _settle();
      s = bloc.state as GameActive;
      expect(s.tauntFromMe, isTrue);
      expect(
        s.tauntSeq,
        firstSeq + 1,
        reason: 'identical taunt must re-trigger',
      );
    },
  );

  test(
    'a taunt added after the client fetched its catalogue still shows',
    () async {
      await startGame();
      ws.emit('taunt', {
        'player_id': _them,
        'taunt': 'brand_new',
        'text': 'پیام تازه',
      });
      await _settle();
      expect((bloc.state as GameActive).tauntText, 'پیام تازه');
    },
  );

  test('a taunt without text is ignored', () async {
    await startGame();
    ws.emit('taunt', {'player_id': _them, 'taunt': 'hurry_up'});
    await _settle();
    expect((bloc.state as GameActive).tauntId, isNull);
  });

  test('TauntSent sends the id (the server owns the catalogue)', () async {
    await startGame(premium: [_me]);
    bloc.add(const TauntSent('hurry_up'));
    bloc.add(const TauntSent(''));
    await _settle();
    expect(ws.sent, [
      {'type': 'send_taunt', 'taunt': 'hurry_up'},
    ]);
  });

  test('taunt_rejected surfaces a Persian notice', () async {
    final before = await startGame();
    ws.emit('taunt_rejected', {'reason': 'premium_required'});
    await _settle();
    var s = bloc.state as GameActive;
    expect(s.powerupNotice, contains('اشتراک ویژه'));
    expect(s.powerupNoticeSeq, before.powerupNoticeSeq + 1);

    ws.emit('taunt_rejected', {'reason': 'rate_limited'});
    await _settle();
    s = bloc.state as GameActive;
    expect(s.powerupNotice, contains('صبر'));
  });
}
