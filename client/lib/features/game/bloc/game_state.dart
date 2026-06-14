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
  final int localMatchId; // -1 for multiplayer (server-managed)
  final String mode;
  final String opponentType;
  final List<String> wordChain;
  final List<int> wordScores; // per-word scores (only for my words)
  final int score;
  final int streak;
  final int turnTimeRemaining;
  final int? matchTimeRemaining; // time_attack only
  final String? nextStartLetter;
  final String? hintWord;
  final int guestHintUsesLeft;
  final bool continueUsed;

  // Multiplayer-specific (solo/AI: isMyTurn=true, rest=default)
  final bool isMyTurn;
  final String? myPlayerId;
  final String? opponentId;
  final String? opponentUsername;
  final int opponentScore;
  final List<String?> wordOwners; // parallel to wordChain — player ID per word
  final bool opponentContinueWindowActive;
  final int opponentContinueWindowRemaining;
  final bool opponentDisconnected;

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
    this.isMyTurn = true,
    this.myPlayerId,
    this.opponentId,
    this.opponentUsername,
    this.opponentScore = 0,
    this.wordOwners = const [],
    this.opponentContinueWindowActive = false,
    this.opponentContinueWindowRemaining = 0,
    this.opponentDisconnected = false,
  });

  GameActive copyWith({
    List<String>? wordChain,
    List<int>? wordScores,
    List<String?>? wordOwners,
    int? score,
    int? streak,
    int? turnTimeRemaining,
    Object? matchTimeRemaining = _sentinel,
    Object? nextStartLetter = _sentinel,
    Object? hintWord = _sentinel,
    int? guestHintUsesLeft,
    bool? continueUsed,
    bool? isMyTurn,
    int? opponentScore,
    bool? opponentContinueWindowActive,
    int? opponentContinueWindowRemaining,
    bool? opponentDisconnected,
  }) {
    return GameActive(
      localMatchId: localMatchId,
      mode: mode,
      opponentType: opponentType,
      wordChain: wordChain ?? this.wordChain,
      wordScores: wordScores ?? this.wordScores,
      wordOwners: wordOwners ?? this.wordOwners,
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
      isMyTurn: isMyTurn ?? this.isMyTurn,
      myPlayerId: myPlayerId,
      opponentId: opponentId,
      opponentUsername: opponentUsername,
      opponentScore: opponentScore ?? this.opponentScore,
      opponentContinueWindowActive:
          opponentContinueWindowActive ?? this.opponentContinueWindowActive,
      opponentContinueWindowRemaining:
          opponentContinueWindowRemaining ?? this.opponentContinueWindowRemaining,
      opponentDisconnected: opponentDisconnected ?? this.opponentDisconnected,
    );
  }

  bool get isMultiplayer => opponentType == 'multiplayer';

  bool get isVsAI => opponentType.startsWith('ai_');

  @override
  List<Object?> get props => [
        localMatchId,
        mode,
        opponentType,
        wordChain,
        wordScores,
        wordOwners,
        score,
        streak,
        turnTimeRemaining,
        matchTimeRemaining,
        nextStartLetter,
        hintWord,
        guestHintUsesLeft,
        continueUsed,
        isMyTurn,
        myPlayerId,
        opponentId,
        opponentUsername,
        opponentScore,
        opponentContinueWindowActive,
        opponentContinueWindowRemaining,
        opponentDisconnected,
      ];
}

class GameOver extends GameState {
  final int localMatchId;
  final String mode;
  final String reason; // invalid_word | timeout | time_limit | ended_by_user | game_over | opponent_disconnected
  final String? rejectedWord;
  final String? rejectionReason; // not_in_dictionary | wrong_letter | already_used | too_short
  final int score;
  final int chainLength;
  final List<String> wordChain;
  final bool canContinue;
  final int continueTimeRemaining;
  final bool isSaved;
  final String? winnerId; // null = solo; player UUID for multiplayer
  final int opponentScore;
  final String? opponentType; // solo | ai_easy | ai_medium | ai_hard | multiplayer

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
    this.winnerId,
    this.opponentScore = 0,
    this.opponentType,
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
      winnerId: winnerId,
      opponentScore: opponentScore,
      opponentType: opponentType,
    );
  }

  bool get isMultiplayer => winnerId != null || opponentScore > 0 || (opponentType != null && opponentType!.startsWith('ai_'));

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
        winnerId,
        opponentScore,
        opponentType,
      ];
}

class GameError extends GameState {
  final String message;

  const GameError(this.message);

  @override
  List<Object?> get props => [message];
}
