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
  final String? nextStartLetter;
  final String? hintWord;
  final int guestHintUsesLeft;
  final bool continueUsed;

  // Lives — solo opponent only, classic and daily modes (see
  // GameConstants.soloLives). AI/multiplayer opponents don't use lives and
  // always report 0 (unused).
  final int livesRemaining;
  final String? lastMistakeReason; // transient — cleared on next word/tick

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

  // Power-ups. `powerupCounts` is the owned inventory (authenticated only);
  // `usedPowerups` enforces once-per-match (multiplayer, daily) / once-per-game
  // (shield); `shieldActive` is solo/AI's armed shield. `powerupNotice` is a
  // transient message — `powerupNoticeSeq` bumps so an identical message still
  // re-triggers the UI listener. `coinBalance` is the balance reported by the
  // last paid use, for the UI to push into AuthCubit.
  final Map<String, int> powerupCounts;
  final Set<String> usedPowerups;
  final bool shieldActive;
  final String? powerupNotice;
  final int powerupNoticeSeq;
  final int? coinBalance;

  const GameActive({
    required this.localMatchId,
    required this.mode,
    required this.opponentType,
    required this.wordChain,
    required this.wordScores,
    required this.score,
    required this.streak,
    required this.turnTimeRemaining,
    this.nextStartLetter,
    this.hintWord,
    required this.guestHintUsesLeft,
    required this.continueUsed,
    this.livesRemaining = 0,
    this.lastMistakeReason,
    this.isMyTurn = true,
    this.myPlayerId,
    this.opponentId,
    this.opponentUsername,
    this.opponentScore = 0,
    this.wordOwners = const [],
    this.opponentContinueWindowActive = false,
    this.opponentContinueWindowRemaining = 0,
    this.opponentDisconnected = false,
    this.powerupCounts = const {},
    this.usedPowerups = const {},
    this.shieldActive = false,
    this.powerupNotice,
    this.powerupNoticeSeq = 0,
    this.coinBalance,
  });

  GameActive copyWith({
    List<String>? wordChain,
    List<int>? wordScores,
    List<String?>? wordOwners,
    int? score,
    int? streak,
    int? turnTimeRemaining,
    Object? nextStartLetter = _sentinel,
    Object? hintWord = _sentinel,
    int? guestHintUsesLeft,
    bool? continueUsed,
    int? livesRemaining,
    Object? lastMistakeReason = _sentinel,
    bool? isMyTurn,
    int? opponentScore,
    bool? opponentContinueWindowActive,
    int? opponentContinueWindowRemaining,
    bool? opponentDisconnected,
    Map<String, int>? powerupCounts,
    Set<String>? usedPowerups,
    bool? shieldActive,
    String? powerupNotice,
    int? coinBalance,
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
      nextStartLetter: nextStartLetter == _sentinel
          ? this.nextStartLetter
          : nextStartLetter as String?,
      hintWord: hintWord == _sentinel ? this.hintWord : hintWord as String?,
      guestHintUsesLeft: guestHintUsesLeft ?? this.guestHintUsesLeft,
      continueUsed: continueUsed ?? this.continueUsed,
      livesRemaining: livesRemaining ?? this.livesRemaining,
      lastMistakeReason: lastMistakeReason == _sentinel
          ? this.lastMistakeReason
          : lastMistakeReason as String?,
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
      powerupCounts: powerupCounts ?? this.powerupCounts,
      usedPowerups: usedPowerups ?? this.usedPowerups,
      shieldActive: shieldActive ?? this.shieldActive,
      powerupNotice: powerupNotice ?? this.powerupNotice,
      powerupNoticeSeq:
          powerupNotice != null ? powerupNoticeSeq + 1 : powerupNoticeSeq,
      coinBalance: coinBalance ?? this.coinBalance,
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
    nextStartLetter,
    hintWord,
    guestHintUsesLeft,
    continueUsed,
    livesRemaining,
    lastMistakeReason,
    isMyTurn,
    myPlayerId,
    opponentId,
    opponentUsername,
    opponentScore,
    opponentContinueWindowActive,
    opponentContinueWindowRemaining,
    opponentDisconnected,
    powerupCounts,
    usedPowerups,
    shieldActive,
    powerupNoticeSeq,
    coinBalance,
  ];
}

class GameOver extends GameState {
  final int localMatchId;
  final String mode;
  final String reason; // invalid_word | timeout | ended_by_user | game_over | opponent_disconnected
  final String? rejectedWord;
  final String? rejectionReason; // not_in_dictionary | wrong_letter | already_used | too_short
  final int score;
  final int chainLength;
  final List<String> wordChain;
  final bool canContinue;
  final int continueTimeRemaining;
  final bool isSaved;
  final String? winnerId; // null = solo; player UUID for multiplayer
  // True multiplayer only: set from `winner == myPlayerId` on game_over. Null
  // while the match is still undecided (my loss_event, continue window open).
  final bool? iWon;
  final int opponentScore;
  final String? opponentType; // solo | ai_easy | ai_medium | ai_hard | multiplayer
  // 1v1 entry fee paid for this match (0 vs AI / solo) and the net coin change
  // after the payout (+fee for the winner, -fee for the loser, 0 on a draw).
  final int entryFee;
  final int coinsNet;

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
    this.iWon,
    this.opponentScore = 0,
    this.opponentType,
    this.entryFee = 0,
    this.coinsNet = 0,
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
      iWon: iWon,
      opponentScore: opponentScore,
      opponentType: opponentType,
      entryFee: entryFee,
      coinsNet: coinsNet,
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
        iWon,
        opponentScore,
        opponentType,
        entryFee,
        coinsNet,
      ];
}

class GameError extends GameState {
  final String message;

  /// The match was cancelled because this player couldn't pay the entry fee.
  final bool insufficientCoins;

  const GameError(this.message, {this.insufficientCoins = false});

  @override
  List<Object?> get props => [message, insufficientCoins];
}
