import 'package:wordchain/core/utils/persian_digits.dart';

abstract final class GameConstants {
  // Mirrors config.EntryFeeCoins on the backend: each human in a 1v1 match pays
  // this to start, and the winner takes the whole pot (2 × fee). Free vs AI.
  static const int entryFeeCoins = 20;
  static const int entryFeePot = entryFeeCoins * 2;
  static const int classicTurnTimerSec = 15;

  /// How long matchmaking waits for a human before pairing the player with
  /// the AI (mirrors `config.AIFallbackWaitSec`).
  static const int matchmakingAiFallbackSec = 30;

  /// How long a friend challenge stays answerable (backend: 24h expiry).
  static const int challengeValidHours = 24;

  /// How long the Friends row keeps «دعوت شد» after a challenge is sent. A UI
  /// debounce only: the server has no duplicate guard and no «who did I
  /// invite» read, so the app can't know the friend declined.
  static const int friendInviteSentSec = 300;

  /// Prizes of the top three, 1st → 3rd (mirror `config.CoinWeeklyRank1..3` and
  /// `config.CoinDailyRank1..3`); claimed from the inbox after the reset.
  static const List<int> weeklyPrizeCoins = [500, 300, 100];
  static const List<int> dailyPrizeCoins = [100, 60, 30];
  static const int continueWindowSec = 15;
  static const int reconnectGraceSec = 30; // server holds the room this long
  static const int continueCostCoins = 25;

  // Taunt limits, per player (mirror config.TauntCooldownSec / TauntMaxPerMatch;
  // the server enforces them, the tray only states them).
  static const int tauntCooldownSec = 5;
  static const int tauntMaxPerMatch = 8;
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

  /// How long a room waits for its second player before the server cancels it
  /// (mirrors `config.RoomWaitTimeoutSec`).
  static const int roomWaitTimeoutSec = 120;

  /// Level titles by minimum level (levels themselves come from the server).
  static const List<(int, String)> levelTitles = [
    (1, 'تازه‌کار'),
    (5, 'واژه‌جو'),
    (10, 'واژه‌باز'),
    (20, 'واژه‌ساز'),
    (35, 'استاد واژه'),
  ];

  static String levelTitle(int level) =>
      levelTitles
          .lastWhere((t) => level >= t.$1, orElse: () => levelTitles.first)
          .$2;

  // Daily Challenge prizes, paid as claimable rewards at Iran midnight. Mirror
  // config.CoinDailyRank1..3 / CoinDailyComplete on the backend.
  static const List<int> dailyRankPrizes = [100, 60, 30];
  static const int dailyCompletePrize = 10;
}

/// The taunt rule as the player reads it (tray sub-line, rejection toast).
String tauntRuleText() =>
    'هر ${toPersianDigits(GameConstants.tauntCooldownSec)} ثانیه یک طعنه · '
    'تا ${toPersianDigits(GameConstants.tauntMaxPerMatch)} طعنه در هر بازی';
