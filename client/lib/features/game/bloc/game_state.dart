import 'package:equatable/equatable.dart';

// Sentinel object used for nullable copyWith parameters
const _sentinel = Object();

sealed class GameState extends Equatable {
  const GameState();
}

class GameInitial extends GameState {
  const GameInitial();

  @override
  List<Object?> get props => [];
}

class GameLoading extends GameState {
  const GameLoading();

  @override
  List<Object?> get props => [];
}

class GameActive extends GameState {
  final int localMatchId;
  final String mode;
  final String opponentType;
  final List<String> wordChain;
  final List<int> wordScores;
  final int score;
  final int streak;
  final int turnTimeRemaining;
  final int? matchTimeRemaining; // only for time_attack
  final String? nextStartLetter;
  final String? hintWord;
  final int guestHintUsesLeft;
  final bool continueUsed;

  const GameActive({
    required this.localMatchId,
    required this.mode,
    required this.opponentType,
    required this.wordChain,
    required this.wordScores,
    required this.score,
    required this.streak,
    required this.turnTimeRemaining,
    this.matchTimeRemaining,
    this.nextStartLetter,
    this.hintWord,
    required this.guestHintUsesLeft,
    required this.continueUsed,
  });

  GameActive copyWith({
    List<String>? wordChain,
    List<int>? wordScores,
    int? score,
    int? streak,
    int? turnTimeRemaining,
    Object? matchTimeRemaining = _sentinel,
    Object? nextStartLetter = _sentinel,
    Object? hintWord = _sentinel,
    int? guestHintUsesLeft,
    bool? continueUsed,
  }) {
    return GameActive(
      localMatchId: localMatchId,
      mode: mode,
      opponentType: opponentType,
      wordChain: wordChain ?? this.wordChain,
      wordScores: wordScores ?? this.wordScores,
      score: score ?? this.score,
      streak: streak ?? this.streak,
      turnTimeRemaining: turnTimeRemaining ?? this.turnTimeRemaining,
      matchTimeRemaining: matchTimeRemaining == _sentinel
          ? this.matchTimeRemaining
          : matchTimeRemaining as int?,
      nextStartLetter: nextStartLetter == _sentinel
          ? this.nextStartLetter
          : nextStartLetter as String?,
      hintWord: hintWord == _sentinel ? this.hintWord : hintWord as String?,
      guestHintUsesLeft: guestHintUsesLeft ?? this.guestHintUsesLeft,
      continueUsed: continueUsed ?? this.continueUsed,
    );
  }

  @override
  List<Object?> get props => [
        localMatchId,
        mode,
        opponentType,
        wordChain,
        wordScores,
        score,
        streak,
        turnTimeRemaining,
        matchTimeRemaining,
        nextStartLetter,
        hintWord,
        guestHintUsesLeft,
        continueUsed,
      ];
}

class GameOver extends GameState {
  final int localMatchId;
  final String mode;
  final String reason; // invalid_word | timeout | time_limit | ended_by_user
  final String? rejectedWord;
  final String? rejectionReason; // not_in_dictionary | wrong_letter | already_used | too_short
  final int score;
  final int chainLength;
  final List<String> wordChain;
  final bool canContinue;
  final int continueTimeRemaining;
  final bool isSaved;

  const GameOver({
    required this.localMatchId,
    required this.mode,
    required this.reason,
    this.rejectedWord,
    this.rejectionReason,
    required this.score,
    required this.chainLength,
    required this.wordChain,
    required this.canContinue,
    required this.continueTimeRemaining,
    required this.isSaved,
  });

  GameOver copyWith({
    int? continueTimeRemaining,
    bool? isSaved,
  }) {
    return GameOver(
      localMatchId: localMatchId,
      mode: mode,
      reason: reason,
      rejectedWord: rejectedWord,
      rejectionReason: rejectionReason,
      score: score,
      chainLength: chainLength,
      wordChain: wordChain,
      canContinue: canContinue,
      continueTimeRemaining: continueTimeRemaining ?? this.continueTimeRemaining,
      isSaved: isSaved ?? this.isSaved,
    );
  }

  @override
  List<Object?> get props => [
        localMatchId,
        mode,
        reason,
        rejectedWord,
        rejectionReason,
        score,
        chainLength,
        wordChain,
        canContinue,
        continueTimeRemaining,
        isSaved,
      ];
}

class GameError extends GameState {
  final String message;

  const GameError(this.message);

  @override
  List<Object?> get props => [message];
}
