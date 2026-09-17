abstract final class GameConstants {
  static const int classicTurnTimerSec = 15;
  static const int timeAttackTurnTimerSec = 8;
  static const int timeAttackMatchDurationSec = 90;
  static const int continueWindowSec = 15;
  static const int continueCostCoins = 25;
  static const int guestHintUsesPerSession = 5;
  static const int minWordLength = 3;
  static const int dailyMaxWords = 20;
  static const int dailyRetryCostCoins = 25;

  // Phase 17 (زنجیر redesign) — Lives, adopted for solo (classic + daily
  // modes) only; see REDESIGN_PLAN.md §1 decision 1. AI keeps instant-loss.
  // Multiplayer also keeps instant-loss, permanently: Stage 4 decided
  // *against* extending lives there — the server is fully authoritative
  // for word validation with no grace period (word_rejected → loss_event
  // immediately), so a lives chip would be decorative and misleading. See
  // REDESIGN_PLAN.md §5's "Decision-table items resolved for this stage".
  static const int soloLives = 2;

  // Phase 17 — long-word bonus (see REDESIGN_PLAN.md §1 decision 4).
  static const int longWordBonusMinLength = 7;
  static const double longWordBonusMultiplier = 2.0;

  // Phase 17 Stage 4 — best-of-5 rounds (see REDESIGN_PLAN.md §1 decision 3).
  // Visual-only placeholder: no round-tracking WS/backend logic exists yet,
  // so ZVersus always displays round 1 of this constant.
  static const int multiplayerRoundsTotal = 5;
}
