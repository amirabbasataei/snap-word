import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/audio_service.dart';
import 'package:wordchain/features/game/audio/game_sounds.dart';
import 'package:wordchain/features/game/bloc/game_state.dart';
import 'package:wordchain/features/game/data/rating_change.dart';

GameActive active({
  String opponentType = 'solo',
  List<String> chain = const ['کتاب'],
  List<String?> owners = const [],
  int streak = 0,
  int time = 15,
  bool myTurn = true,
  int lives = 2,
  bool shield = false,
  Set<String> used = const {},
  String? hint,
}) => GameActive(
  localMatchId: 1,
  mode: 'classic',
  opponentType: opponentType,
  wordChain: chain,
  wordScores: const [],
  wordOwners: owners,
  score: 0,
  streak: streak,
  turnTimeRemaining: time,
  guestHintUsesLeft: 5,
  continueUsed: false,
  livesRemaining: lives,
  isMyTurn: myTurn,
  myPlayerId: opponentType == 'multiplayer' ? 'me' : 'player',
  shieldActive: shield,
  usedPowerups: used,
  hintWord: hint,
);

GameOver over({
  String reason = 'invalid_word',
  bool? iWon,
  RatingChange? rating,
}) => GameOver(
  localMatchId: 1,
  mode: 'classic',
  reason: reason,
  score: 0,
  chainLength: 1,
  wordChain: const [],
  canContinue: false,
  continueTimeRemaining: 0,
  isSaved: true,
  iWon: iWon,
  rating: rating,
);

void main() {
  group('words', () {
    test('my solo word chimes and lands on the chain', () {
      final out = soundsForTransition(
        active(),
        active(chain: ['کتاب', 'بهار']),
      );
      expect(out, [Sound.accepted, Sound.tileLand]);
    });

    test('a third word in a row plays the streak sound instead', () {
      final out = soundsForTransition(
        active(streak: 2),
        active(chain: ['کتاب', 'بهار'], streak: 3),
      );
      expect(out, [Sound.streak, Sound.tileLand]);
    });

    test('a word of 7 letters or more plays the long-word run', () {
      final out = soundsForTransition(
        active(streak: 2),
        active(chain: ['کتاب', 'بازیگران'], streak: 3),
      );
      expect(out.first, Sound.longWord);
    });

    test('half-spaces do not make a word long', () {
      // «آب‌بازی» is 6 letters (7 runes): no long-word bonus.
      final out = soundsForTransition(
        active(),
        active(chain: ['کتاب', 'آب‌بازی']),
      );
      expect(out.first, Sound.accepted);
    });

    test('the AI answering is a softer opponent word, not my chime', () {
      final out = soundsForTransition(
        active(opponentType: 'ai_easy', owners: ['player'], chain: ['کتاب']),
        active(
          opponentType: 'ai_easy',
          owners: ['player', 'ai'],
          chain: ['کتاب', 'بهار'],
        ),
      );
      expect(out, [Sound.oppWord, Sound.tileLand]);
    });

    test('online: the owner id decides whose word it is', () {
      final mine = soundsForTransition(
        active(opponentType: 'multiplayer', owners: ['x'], chain: ['کتاب']),
        active(
          opponentType: 'multiplayer',
          owners: ['x', 'me'],
          chain: ['کتاب', 'بهار'],
        ),
      );
      final theirs = soundsForTransition(
        active(opponentType: 'multiplayer', owners: ['me'], chain: ['کتاب']),
        active(
          opponentType: 'multiplayer',
          owners: ['me', 'x'],
          chain: ['کتاب', 'بهار'],
        ),
      );
      expect(mine.first, Sound.accepted);
      expect(theirs.first, Sound.oppWord);
    });
  });

  group('mistakes and power-ups', () {
    test('losing a life', () {
      expect(
        soundsForTransition(active(lives: 2), active(lives: 1)),
        [Sound.lifeLost],
      );
    });

    test('a shield arming and being spent', () {
      expect(
        soundsForTransition(active(), active(shield: true)),
        [Sound.shield],
      );
      expect(
        soundsForTransition(active(shield: true), active()),
        [Sound.shield],
      );
      expect(
        soundsForTransition(active(), active(used: {'shield'})),
        [Sound.shield],
      );
    });

    test('hint and extra time', () {
      expect(
        soundsForTransition(active(), active(hint: 'بهار')),
        [Sound.hint],
      );
      expect(
        soundsForTransition(active(), active(used: {'extra_time'})),
        [Sound.extraTime],
      );
    });

    test('the clock ticks for my turn in the last 5 seconds only', () {
      expect(soundsForTransition(active(time: 6), active(time: 5)), [Sound.tick]);
      expect(soundsForTransition(active(time: 2), active(time: 1)), [Sound.tick]);
      expect(soundsForTransition(active(time: 9), active(time: 8)), isEmpty);
      expect(soundsForTransition(active(time: 1), active(time: 0)), isEmpty);
      expect(
        soundsForTransition(
          active(time: 4, myTurn: false),
          active(time: 3, myTurn: false),
        ),
        isEmpty,
      );
    });
  });

  group('match start and end', () {
    test('only an online match has a "found you" sound', () {
      expect(
        soundsForTransition(
          const GameLoading(),
          active(opponentType: 'multiplayer'),
        ),
        [Sound.matchFound],
      );
      expect(soundsForTransition(const GameLoading(), active()), isEmpty);
      // continuing after a loss is not a start
      expect(soundsForTransition(over(), active(opponentType: 'multiplayer')), isEmpty);
    });

    test('win and lose', () {
      expect(soundsForTransition(active(), over(iWon: true)), [Sound.win]);
      expect(soundsForTransition(active(), over(iWon: false)), [Sound.lose]);
    });

    test('a solo run ends with the sound of what ended it', () {
      expect(
        soundsForTransition(active(), over(reason: 'timeout')),
        [Sound.timeout],
      );
      expect(
        soundsForTransition(active(), over(reason: 'invalid_word')),
        [Sound.rejected],
      );
      expect(
        soundsForTransition(active(), over(reason: 'ended_by_user')),
        isEmpty,
      );
    });

    test('a loss that becomes final plays the result once', () {
      expect(
        soundsForTransition(over(reason: 'timeout'), over(reason: 'timeout', iWon: false)),
        [Sound.lose],
      );
      expect(
        soundsForTransition(over(iWon: false), over(iWon: false)),
        isEmpty,
      );
    });

    test('the «جام» change plays up or down, nothing for 0', () {
      const up = RatingChange(before: 1000, after: 1016, delta: 16);
      const down = RatingChange(before: 1000, after: 990, delta: -10);
      const flat = RatingChange(before: 1000, after: 1000, delta: 0);
      expect(
        soundsForTransition(over(iWon: true), over(iWon: true, rating: up)),
        [Sound.ratingUp],
      );
      expect(
        soundsForTransition(over(iWon: false), over(iWon: false, rating: down)),
        [Sound.ratingDown],
      );
      expect(
        soundsForTransition(over(iWon: true), over(iWon: true, rating: flat)),
        isEmpty,
      );
    });
  });
}
