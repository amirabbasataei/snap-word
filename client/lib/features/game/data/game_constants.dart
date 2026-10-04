abstract final class GameConstants {
  // Mirrors config.EntryFeeCoins on the backend: each human in a 1v1 match pays
  // this to start, and the winner takes the whole pot (2 × fee). Free vs AI.
  static const int entryFeeCoins = 20;
  static const int entryFeePot = entryFeeCoins * 2;
  static const int classicTurnTimerSec = 15;
  static const int continueWindowSec = 15;
  static const int reconnectGraceSec = 30; // server holds the room this long
  static const int continueCostCoins = 25;
  static const int guestHintUsesPerSession = 5;

  // Power-ups: a use comes out of the owned inventory first, otherwise it costs
  // coins (server-authoritative). Mirror config.CoinHint/Freeze/ExtraTime/Shield.
  static const Map<String, int> powerupCostCoins = {
    'hint': 10,
    'freeze': 20,
    'extra_time': 15,
    'shield': 20,
  };
  static const int extraTimeBonusSec = 8;
  static const int rewardedAdCoins = 20; // mirrors config.CoinRewardedAd
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

  // Daily Challenge prizes, paid as claimable rewards at Iran midnight. Mirror
  // config.CoinDailyRank1..3 / CoinDailyComplete on the backend.
  static const List<int> dailyRankPrizes = [100, 60, 30];
  static const int dailyCompletePrize = 10;
}
