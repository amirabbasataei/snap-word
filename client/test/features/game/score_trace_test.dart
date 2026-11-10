import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/database/app_database.dart';
import 'package:wordchain/features/game/bloc/game_bloc.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/game/data/score_trace.dart';

/// The same vectors as backend/internal/engine/scorer_test.go
/// (`scoreVectors`): every mode scores with this formula and the server
/// recomputes an uploaded Daily score with its own copy, so both must give
/// these exact numbers.
const _vectors = <(String, String, int, int, int)>[
  ('plain', 'سلام', 4000, 0, 62),
  ('streak bonus from three', 'سلام', 4000, 3, 82),
  ('no streak bonus at two', 'سلام', 4000, 2, 62),
  ('slow answer has no speed bonus', 'کتاب', 15000, 0, 40),
  ('slower than the limit stays at base', 'کتاب', 16000, 0, 40),
  ('fastest answer truncates 29.4', 'آب', 300, 5, 59),
  ('seven letters: +15', 'دانشگاه', 2500, 4, 145),
  ('nine letters: +45', 'دانشجویان', 3000, 0, 159),
  ('ten letters with streak: +60', 'کتابخانه‌ها', 4000, 3, 232),
  ('half-space is not a letter', 'می‌روم', 1234, 0, 77),
  ('six letters with a half-space get no bonus', 'آب‌بازی', 5000, 0, 80),
  ('seven letters counting a half-space: +15', 'می‌خواهم', 15000, 0, 85),
];

void main() {
  group('calculateScore matches the Go engine.CalculateScore vectors', () {
    for (final (name, word, ms, streak, want) in _vectors) {
      test(name, () {
        expect(GameBloc.calculateScore(word, ms / 1000.0, streak, 15), want);
      });
    }
  });

  test('longWordBonus is smooth: nothing to 6 letters, then +15 each', () {
    const want = {0: 0, 3: 0, 6: 0, 7: 15, 8: 30, 9: 45, 12: 90};
    want.forEach((letters, bonus) {
      expect(GameBloc.longWordBonus(letters), bonus, reason: '$letters');
    });
  });

  group('ScoreTrace', () {
    test('round-trips through JSON and appends', () {
      final t = ScoreTrace.empty.add(4000, 0).add(2500, 1);
      final back = ScoreTrace.parse(t.toJson());
      expect(back.timesMs, [4000, 2500]);
      expect(back.streaks, [0, 1]);
    });

    test('malformed or missing data reads as empty', () {
      expect(ScoreTrace.parse(null).timesMs, isEmpty);
      expect(ScoreTrace.parse('').timesMs, isEmpty);
      expect(ScoreTrace.parse('not json').timesMs, isEmpty);
      expect(ScoreTrace.parse('{"t":[1],"s":[]}').timesMs, isEmpty);
      expect(ScoreTrace.parse('{"t":"x","s":[]}').timesMs, isEmpty);
    });

    test('covers needs exactly one entry per chain word', () {
      final t = ScoreTrace.empty.add(4000, 0).add(2500, 1);
      expect(t.covers(['سلام', 'مرغ']), isTrue);
      expect(t.covers(['سلام']), isFalse);
      expect(t.covers(['سلام', 'مرغ', 'غاز']), isFalse);
      expect(ScoreTrace.empty.covers([]), isFalse);
    });

    test('scoreFromTrace is the sum of the turn scores', () {
      final chain = ['سلام', 'مرغ'];
      final t = ScoreTrace.empty.add(4000, 0).add(2500, 1);
      expect(
        GameBloc.scoreFromTrace(chain, t),
        GameBloc.calculateScore('سلام', 4, 0, 15) +
            GameBloc.calculateScore('مرغ', 2.5, 1, 15),
      );
    });
  });

  group('GameRepository keeps the trace with the match', () {
    late AppDatabase db;
    late GameRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = GameRepository(
        db: db,
        matchDao: db.matchDao,
        usedWordDao: db.usedWordDao,
        dio: Dio(),
      );
    });
    tearDown(() => db.close());

    test('each accepted word appends its time and streak', () async {
      final id = await repo.startLocalGame('daily', 'solo');
      await repo.recordAcceptedWord(id, ['سلام'], responseMs: 4000, streak: 0);
      await repo.recordAcceptedWord(
        id,
        ['سلام', 'مرغ'],
        responseMs: 2500,
        streak: 1,
      );
      final row = await repo.getMatchById(id);
      final trace = ScoreTrace.parse(row!.scoreTrace);
      expect(trace.timesMs, [4000, 2500]);
      expect(trace.streaks, [0, 1]);
      expect(trace.covers(['سلام', 'مرغ']), isTrue);
    });

    test('a word recorded without timing leaves the trace alone', () async {
      final id = await repo.startLocalGame('classic', 'ai_easy');
      await repo.recordAcceptedWord(id, ['سلام'], responseMs: 3000, streak: 0);
      await repo.recordAcceptedWord(id, ['سلام', 'مرغ']); // the AI's word
      final trace = ScoreTrace.parse((await repo.getMatchById(id))!.scoreTrace);
      expect(trace.timesMs, [3000]);
      expect(trace.covers(['سلام', 'مرغ']), isFalse);
    });
  });

  test('a v2 database upgrades to v3 without losing a match', () async {
    final dir = await Directory.systemTemp.createTemp('wc_db_v2');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.db');
    // `setup` runs on the raw connection before drift reads the schema
    // version: a fresh file is given the v2 layout and version, so drift
    // runs its real v2 → v3 upgrade when it opens.
    final db = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('''
            CREATE TABLE local_matches (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              remote_id TEXT NULL,
              mode TEXT NOT NULL,
              opponent_type TEXT NOT NULL,
              status TEXT NOT NULL,
              score INTEGER NOT NULL DEFAULT 0,
              chain_length INTEGER NOT NULL DEFAULT 0,
              word_chain TEXT NOT NULL DEFAULT '[]',
              synced INTEGER NOT NULL DEFAULT 0 CHECK (synced IN (0, 1)),
              started_at INTEGER NOT NULL,
              ended_at INTEGER NULL
            );
            INSERT INTO local_matches (mode, opponent_type, status, score, word_chain, started_at)
              VALUES ('daily', 'solo', 'active', 0, '["سلام"]', 1700000000);
            PRAGMA user_version = 2;
          ''');
        },
      ),
    );
    addTearDown(db.close);
    final rows = await db.select(db.localMatches).get();
    expect(rows, hasLength(1));
    expect(rows.single.wordChain, '["سلام"]');
    expect(rows.single.scoreTrace, isNull);
    // The column is writable after the upgrade.
    await db.matchDao.updateWordChainForMatch(rows.single.id, [
      'سلام',
      'مرغ',
    ], scoreTrace: ScoreTrace.empty.add(4000, 0).toJson());
    final after = await db.select(db.localMatches).getSingle();
    expect(ScoreTrace.parse(after.scoreTrace).timesMs, [4000]);
  });
}
