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
const _ai = '00000000-0000-0000-0000-000000000001';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _FakeWs ws;
  late GameBloc bloc;

  Future<void> start({
    required Map<String, dynamic> ratings,
    String opponent = _them,
    Map<String, dynamic>? usernames,
  }) async {
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
        'players': [_me, opponent],
        'mode': 'classic',
        'current_turn': _me,
        'ratings': ratings,
        if (usernames != null) 'usernames': usernames,
      },
    });
    await _settle();
  }

  tearDown(() => bloc.close());

  group('game_start ratings', () {
    test('both players\' جام reach the active state', () async {
      await start(ratings: {_me: 1016, _them: 984});
      final active = bloc.state as GameActive;
      expect(active.myRating, 1016);
      expect(active.opponentRating, 984);
      expect(active.opponentIsAi, isFalse);
    });

    test('an opponent missing from a map that has mine is the AI', () async {
      await start(ratings: {_me: 1016}, opponent: _ai);
      final active = bloc.state as GameActive;
      expect(active.myRating, 1016);
      expect(active.opponentRating, isNull);
      expect(active.opponentIsAi, isTrue);
    });

    test(
      'no ratings at all (old server, failed lookup): nothing is guessed',
      () async {
        await start(ratings: const {});
        final active = bloc.state as GameActive;
        expect(active.myRating, isNull);
        expect(active.opponentRating, isNull);
        expect(active.opponentIsAi, isFalse);
      },
    );
  });

  group('game_start usernames', () {
    test('the opponent\'s username reaches the active state', () async {
      await start(
        ratings: {_me: 1000, _them: 1000},
        usernames: {_me: 'sara', _them: 'ali_99'},
      );
      expect((bloc.state as GameActive).opponentUsername, 'ali_99');
    });

    test('no username (AI fallback, old server): stays null', () async {
      await start(
        ratings: {_me: 1000},
        opponent: _ai,
        usernames: {_me: 'sara'},
      );
      expect((bloc.state as GameActive).opponentUsername, isNull);
    });
  });

  group('rating_update', () {
    test('lands on the result screen that game_over already raised', () async {
      await start(ratings: {_me: 1000, _them: 1000});
      ws.emit('loss_event', {'player_id': _them, 'reason': 'timeout'});
      ws.emit('game_over', {
        'winner': _me,
        'scores': {_me: 40, _them: 10},
      });
      await _settle();
      expect((bloc.state as GameOver).rating, isNull);

      ws.emit('rating_update', {
        'rating': {
          _me: {'before': 1000, 'after': 1016, 'delta': 16},
          _them: {'before': 1000, 'after': 984, 'delta': -16},
        },
      });
      await _settle();

      final over = bloc.state as GameOver;
      expect(over.iWon, isTrue);
      expect(over.rating?.before, 1000);
      expect(over.rating?.after, 1016);
      expect(over.rating?.delta, 16);
      expect(over.ratingPairCap, isFalse);
      // The rest of the result is untouched.
      expect(over.score, 40);
      expect(over.opponentScore, 10);
    });

    test('a loss shows my negative delta, not the opponent\'s', () async {
      await start(ratings: {_me: 1000, _them: 1000});
      ws.emit('loss_event', {'player_id': _me, 'reason': 'timeout'});
      ws.emit('game_over', {
        'winner': _them,
        'scores': {_me: 0, _them: 0},
      });
      ws.emit('rating_update', {
        'rating': {
          _me: {'before': 1000, 'after': 984, 'delta': -16},
          _them: {'before': 1000, 'after': 1016, 'delta': 16},
        },
      });
      await _settle();
      final over = bloc.state as GameOver;
      expect(over.rating?.delta, -16);
      expect(over.rating?.after, 984);
    });

    test('pair_cap: nothing moved, and the screen is told why', () async {
      await start(ratings: {_me: 1100, _them: 1100});
      ws.emit('game_over', {
        'winner': _me,
        'scores': {_me: 1, _them: 0},
      });
      ws.emit('rating_update', {
        'reason': 'pair_cap',
        'rating': {
          _me: {'before': 1100, 'after': 1100, 'delta': 0},
          _them: {'before': 1100, 'after': 1100, 'delta': 0},
        },
      });
      await _settle();
      final over = bloc.state as GameOver;
      expect(over.rating?.delta, 0);
      expect(over.ratingPairCap, isTrue);
    });

    test(
      'the AI fallback is remembered on the result, with no rating',
      () async {
        await start(ratings: {_me: 1000}, opponent: _ai);
        ws.emit('game_over', {
          'winner': _me,
          'scores': {_me: 5, _ai: 0},
        });
        await _settle();
        final over = bloc.state as GameOver;
        expect(over.opponentIsAi, isTrue);
        expect(over.rating, isNull);
      },
    );

    test('a malformed or foreign update changes nothing', () async {
      await start(ratings: {_me: 1000, _them: 1000});
      ws.emit('game_over', {
        'winner': _me,
        'scores': {_me: 5, _them: 0},
      });
      await _settle();
      ws.emit('rating_update', {
        'rating': {
          'someone-else': {'before': 1000, 'after': 1016, 'delta': 16},
        },
      });
      ws.emit('rating_update', {
        'rating': {
          _me: {'before': 'x'},
        },
      });
      ws.emit('rating_update', <String, dynamic>{});
      await _settle();
      expect((bloc.state as GameOver).rating, isNull);
    });

    test('an update outside a result screen is ignored', () async {
      await start(ratings: {_me: 1000, _them: 1000});
      ws.emit('rating_update', {
        'rating': {
          _me: {'before': 1000, 'after': 1016, 'delta': 16},
        },
      });
      await _settle();
      expect(bloc.state, isA<GameActive>());
    });

    test('the ticking continue timer does not drop the rating', () async {
      await start(ratings: {_me: 1000, _them: 1000});
      ws.emit('game_over', {
        'winner': _me,
        'scores': {_me: 5, _them: 0},
      });
      ws.emit('rating_update', {
        'rating': {
          _me: {'before': 1000, 'after': 1016, 'delta': 16},
        },
      });
      await _settle();
      final over = bloc.state as GameOver;
      expect(over.copyWith(isSaved: true).rating, over.rating);
    });
  });
}
