import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/core/services/dictionary_service.dart';
import 'package:wordchain/core/services/sync_service.dart';
import 'package:wordchain/core/services/websocket_service.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_constants.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/game/data/score_trace.dart';

/// کتاب → بار → راه → هوا → اسب.
const _chain = ['کتاب', 'بار', 'راه', 'هوا', 'اسب'];

class _Dictionary extends Fake implements DictionaryService {
  @override
  bool isValid(String word) => _chain.contains(word);
}

class _FakeSync extends Fake implements SyncService {
  @override
  Future<void> sync() async {}
}

/// Records the body of every POST so the upload can be inspected.
class _Capture implements HttpClientAdapter {
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      bodies.add(Map<String, dynamic>.from(options.data as Map));
      return ResponseBody.fromString(
        jsonEncode({
          'data': {'id': 'remote-${bodies.length}'},
        }),
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'data': <String, dynamic>{}}),
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late AppDatabase db;
  late GameRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = GameRepository(
      db: db,
      matchDao: db.matchDao,
      usedWordDao: db.usedWordDao,
      dio: Dio(),
    );
  });
  tearDown(() => db.close());

  Future<GameBloc> newBloc() async => GameBloc(
    gameRepository: repo,
    dictionaryService: _Dictionary(),
    statsDao: db.statsDao,
    syncService: _FakeSync(),
    prefs: await SharedPreferences.getInstance(),
    wsService: WebSocketService(),
  );

  test(
    'a Daily run records time and streak per word, across a lost life',
    () async {
      final bloc = await newBloc();
      addTearDown(bloc.close);
      bloc.add(
        const GameStarted(
          mode: 'daily',
          opponentType: 'solo',
          startLetter: 'ک',
        ),
      );
      await _settle();
      bloc.add(WordSubmitted(_chain[0]));
      await _settle();
      bloc.add(WordSubmitted(_chain[1]));
      await _settle();
      bloc.add(
        const WordSubmitted('هلو'),
      ); // refused: costs a life, resets the streak
      await _settle();
      bloc.add(WordSubmitted(_chain[2]));
      await _settle();

      final active = bloc.state as GameActive;
      final row = (await db.select(db.localMatches).get()).single;
      final trace = ScoreTrace.parse(row.scoreTrace);
      expect(trace.streaks, [0, 1, 0]);
      expect(trace.timesMs, hasLength(3));
      expect(trace.timesMs.every((t) => t >= 0), isTrue);
      expect(trace.covers(active.wordChain), isTrue);
      // The score on screen is exactly what the server recomputes from the trace.
      expect(GameBloc.scoreFromTrace(active.wordChain, trace), active.score);
    },
  );

  test(
    'a resumed solo run gets its earned score back from the trace',
    () async {
      final id = await repo.startLocalGame('daily', 'solo');
      await repo.recordAcceptedWord(
        id,
        [_chain[0]],
        responseMs: 4000,
        streak: 0,
      );
      await repo.recordAcceptedWord(
        id,
        [_chain[0], _chain[1]],
        responseMs: 2500,
        streak: 1,
      );
      final earned =
          GameBloc.calculateScore(_chain[0], 4, 0, 15) +
          GameBloc.calculateScore(_chain[1], 2.5, 1, 15);

      final bloc = await newBloc();
      addTearDown(bloc.close);
      bloc.add(
        GameStarted(mode: 'daily', opponentType: 'solo', resumeMatchId: id),
      );
      await _settle();
      expect((bloc.state as GameActive).score, earned);
      expect(
        (bloc.state as GameActive).livesRemaining,
        GameConstants.soloLives,
      );
    },
  );

  test(
    'a resumed run without a matching trace keeps the old behaviour',
    () async {
      final id = await repo.startLocalGame('classic', 'solo');
      await repo.recordAcceptedWord(id, [
        _chain[0],
      ]); // no timing: pre-trace row
      final bloc = await newBloc();
      addTearDown(bloc.close);
      bloc.add(
        GameStarted(mode: 'classic', opponentType: 'solo', resumeMatchId: id),
      );
      await _settle();
      expect((bloc.state as GameActive).score, 0);
    },
  );

  group('SyncService uploads the trace for Daily runs only', () {
    late _Capture capture;
    late SyncService sync;

    setUp(() {
      SharedPreferences.setMockInitialValues({'jwt_access_token': 'x'});
      capture = _Capture();
    });

    Future<void> uploadRun(String mode, {bool withTrace = true}) async {
      final id = await repo.startLocalGame(mode, 'solo');
      await repo.recordAcceptedWord(
        id,
        [_chain[0]],
        responseMs: withTrace ? 4000 : null,
        streak: withTrace ? 0 : null,
      );
      await repo.finishLocalGame(id, 62, [_chain[0]]);
      final dio = Dio()..httpClientAdapter = capture;
      sync = SyncService(
        prefs: await SharedPreferences.getInstance(),
        dio: dio,
        matchDao: db.matchDao,
        statsDao: db.statsDao,
        powerupCacheDao: db.powerupCacheDao,
      );
      await sync.sync();
    }

    test('daily with a trace sends word_times_ms and word_streaks', () async {
      await uploadRun('daily');
      expect(capture.bodies, hasLength(1));
      expect(capture.bodies.single['word_times_ms'], [4000]);
      expect(capture.bodies.single['word_streaks'], [0]);
    });

    test('classic never sends a trace', () async {
      await uploadRun('classic');
      expect(capture.bodies.single.containsKey('word_times_ms'), isFalse);
    });

    test('a daily run that has no trace is uploaded without one', () async {
      await uploadRun('daily', withTrace: false);
      expect(capture.bodies, hasLength(1));
      expect(capture.bodies.single.containsKey('word_times_ms'), isFalse);
      expect(capture.bodies.single.containsKey('word_streaks'), isFalse);
    });
  });
}
