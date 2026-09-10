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

  // Phase 17 (زنجیر redesign) — Lives, adopted for the solo opponent only
  // (classic + daily modes; see REDESIGN_PLAN.md §1 decision 1); AI and
  // multiplayer keep instant-loss until Stage 4 extends lives to ZVersus.
  static const int soloLives = 2;

  // Phase 17 — long-word bonus (see REDESIGN_PLAN.md §1 decision 4).
  static const int longWordBonusMinLength = 7;
  static const double longWordBonusMultiplier = 2.0;
}
