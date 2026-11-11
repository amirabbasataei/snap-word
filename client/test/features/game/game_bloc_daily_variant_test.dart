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

/// The feature request's examples: باران → انتظار → ارشاد links on the 2nd
/// letter, باران → بانی → اعیاد on the 3rd. «نان» / «نارنج» are classic
/// links of باران.
const _words = ['باران', 'انتظار', 'ارشاد', 'بانی', 'اعیاد', 'نان', 'نارنج'];

class _FakeSync extends Fake implements SyncService {
  @override
  Future<void> sync() async {}
}

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
    dictionaryService: DictionaryService.withWords(_words),
    statsDao: db.statsDao,
    syncService: _FakeSync(),
    prefs: await SharedPreferences.getInstance(),
    wsService: WebSocketService(),
  );

  Future<GameBloc> start(int variant, String letter) async {
    final bloc = await newBloc();
    addTearDown(bloc.close);
    bloc.add(
      GameStarted(
        mode: 'daily',
        opponentType: 'solo',
        startLetter: letter,
        linkPosition: variant,
      ),
    );
    await _settle();
    return bloc;
  }

  Future<GameActive> submit(GameBloc bloc, String word) async {
    bloc.add(WordSubmitted(word));
    await _settle();
    return bloc.state as GameActive;
  }

  test('2nd letter: words link on their second letter', () async {
    final bloc = await start(2, 'ا');
    var s = bloc.state as GameActive;
    expect(s.linkPosition, 2);
    expect(s.turnTimeRemaining, GameConstants.dailyTurnTimerSec(2));
    expect(s.turnTimeRemaining, 20);

    s = await submit(bloc, 'باران'); // 2nd letter ا = the day's letter
    expect(s.wordChain, ['باران']);
    expect(s.nextStartLetter, 'ن');

    // «نان» starts with ن (a classic link) but its 2nd letter is ا.
    s = await submit(bloc, 'نان');
    expect(s.lastMistakeReason, 'wrong_letter');
    expect(s.livesRemaining, GameConstants.soloLives - 1);
    expect(s.wordChain, ['باران']);

    s = await submit(bloc, 'انتظار');
    s = await submit(bloc, 'ارشاد');
    expect(s.wordChain, ['باران', 'انتظار', 'ارشاد']);

    final row = (await db.select(db.localMatches).get()).single;
    expect(row.linkPosition, 2);
  });

  test('the first word must carry the day\'s letter at the position', () async {
    final bloc = await start(2, 'ا');
    // «بانی» has ا 2nd too: fine. «نان» has ا 2nd: fine. «انتظار» has ن 2nd.
    final s = await submit(bloc, 'انتظار');
    expect(s.lastMistakeReason, 'wrong_letter');
    expect(s.wordChain, isEmpty);
  });

  test('3rd letter: words link on their third letter, 25 s a turn', () async {
    final bloc = await start(3, 'ر');
    expect((bloc.state as GameActive).turnTimeRemaining, 25);
    var s = await submit(bloc, 'باران'); // ب ا ر…
    s = await submit(bloc, 'نارنج'); // classic link, 3rd letter ر
    expect(s.lastMistakeReason, 'wrong_letter');
    s = await submit(bloc, 'بانی');
    s = await submit(bloc, 'اعیاد');
    expect(s.wordChain, ['باران', 'بانی', 'اعیاد']);
  });

  test('a link position is only honoured in the Daily Challenge', () async {
    final bloc = await newBloc();
    addTearDown(bloc.close);
    bloc.add(
      const GameStarted(mode: 'classic', opponentType: 'solo', linkPosition: 3),
    );
    await _settle();
    final s = bloc.state as GameActive;
    expect(s.linkPosition, 1);
    expect(s.turnTimeRemaining, GameConstants.classicTurnTimerSec);
  });

  test('a hint suggests a word linked on the variant\'s letter', () async {
    final bloc = await start(2, 'ا');
    await submit(bloc, 'باران');
    bloc.add(const PowerupRequested('hint'));
    await _settle();
    final hint = (bloc.state as GameActive).hintWord;
    expect(hint, isNotNull);
    expect(DictionaryService.letterAt(hint!, 2), 'ن');
  });

  test('a resumed variant run keeps its rule, timer and score', () async {
    final id = await repo.startLocalGame('daily', 'solo', linkPosition: 2);
    await repo.recordAcceptedWord(id, ['باران'], responseMs: 4000, streak: 0);
    final bloc = await newBloc();
    addTearDown(bloc.close);
    bloc.add(
      GameStarted(mode: 'daily', opponentType: 'solo', resumeMatchId: id),
    );
    await _settle();
    var s = bloc.state as GameActive;
    expect(s.linkPosition, 2);
    expect(s.turnTimeRemaining, 20);
    // Scored with the variant's 20 s timer, as the server recomputes it.
    expect(s.score, GameBloc.calculateScore('باران', 4, 0, 20));
    s = await submit(bloc, 'انتظار');
    expect(s.wordChain, ['باران', 'انتظار']);
  });

  test(
    'a run resumed before its first word still checks the day\'s letter',
    () async {
      final bloc = await start(2, 'ا');
      final row = (await db.select(db.localMatches).get()).single;
      expect(row.startLetter, 'ا');
      await bloc.close();

      // Home's resume passes no start letter: it comes from the row.
      final resumed = await newBloc();
      addTearDown(resumed.close);
      resumed.add(
        GameStarted(mode: 'daily', opponentType: 'solo', resumeMatchId: row.id),
      );
      await _settle();
      var s = resumed.state as GameActive;
      expect(s.nextStartLetter, 'ا');
      s = await submit(resumed, 'انتظار'); // ن 2nd, not ا
      expect(s.lastMistakeReason, 'wrong_letter');
      s = await submit(resumed, 'باران');
      expect(s.wordChain, ['باران']);
    },
  );

  test('only a Daily run stores a start letter', () async {
    final bloc = await newBloc();
    addTearDown(bloc.close);
    bloc.add(
      const GameStarted(
        mode: 'classic',
        opponentType: 'solo',
        startLetter: 'ب',
      ),
    );
    await _settle();
    final row = (await db.select(db.localMatches).get()).single;
    expect(row.startLetter, isNull);
  });

  test(
    'the score on screen equals the trace recomputed with the variant timer',
    () async {
      final bloc = await start(3, 'ر');
      await submit(bloc, 'باران');
      final s = await submit(bloc, 'بانی');
      final row = (await db.select(db.localMatches).get()).single;
      final trace = ScoreTrace.parse(row.scoreTrace);
      expect(
        GameBloc.scoreFromTrace(s.wordChain, trace, timeLimitSec: 25),
        s.score,
      );
    },
  );

  test('SyncService names the daily variant of the run', () async {
    SharedPreferences.setMockInitialValues({'jwt_access_token': 'x'});
    final capture = _Capture();
    Future<void> upload(String mode, int position) async {
      final id = await repo.startLocalGame(
        mode,
        'solo',
        linkPosition: position,
      );
      await repo.recordAcceptedWord(id, ['باران'], responseMs: 4000, streak: 0);
      await repo.finishLocalGame(id, 50, ['باران']);
    }

    await upload('daily', 3);
    await upload('classic', 1);
    final sync = SyncService(
      prefs: await SharedPreferences.getInstance(),
      dio: Dio()..httpClientAdapter = capture,
      matchDao: db.matchDao,
      statsDao: db.statsDao,
      powerupCacheDao: db.powerupCacheDao,
    );
    await sync.sync();
    final daily = capture.bodies.firstWhere((b) => b['mode'] == 'daily');
    final classic = capture.bodies.firstWhere((b) => b['mode'] == 'classic');
    expect(daily['daily_variant'], 3);
    expect(classic.containsKey('daily_variant'), isFalse);
  });

  group('DictionaryService link helpers', () {
    test('letterAt skips the half-space and is null past the end', () {
      expect(DictionaryService.letterAt('باران', 2), 'ا');
      expect(DictionaryService.letterAt('می‌روم', 3), 'ر');
      expect(DictionaryService.letterAt('آب', 3), isNull);
      expect(DictionaryService.letterIndex('می‌روم', 3), 3);
    });

    test('suggestWords filters on the position', () {
      final d = DictionaryService.withWords(_words);
      expect(d.suggestWords('ن', position: 2), ['انتظار']);
      expect(d.suggestWords('ن'), containsAll(['نان', 'نارنج']));
    });
  });
}
