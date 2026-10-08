package config

import (
	"os"
	"time"
)

// Config holds all runtime configuration loaded from environment variables.
// Game tuning constants (timers, costs, limits) live as typed consts below —
// never hardcode them in handlers, services, or Flutter widgets.
type Config struct {
	Port              string
	DatabaseURL       string
	RedisURL          string
	JWTSecret         string
	JWTAccessTTL      time.Duration
	JWTRefreshTTL     time.Duration
	LogLevel          string
	Env               string
	CORSOrigins       string
	FCMProjectID      string
	FCMServiceAccount string
	GameEpochDate     string

	KavenegarAPIKey      string
	KavenegarOTPTemplate string
	OTPCodeTTL           time.Duration
	OTPResendCooldown    time.Duration
}

// Load reads all values from environment variables, falling back to safe defaults.
func Load() *Config {
	return &Config{
		Port:              getEnv("PORT", "8080"),
		DatabaseURL:       getEnv("DATABASE_URL", "postgres://wordchain:wordchain@localhost:5432/wordchain?sslmode=disable"),
		RedisURL:          getEnv("REDIS_URL", "redis://localhost:6379/0"),
		JWTSecret:         getEnv("JWT_SECRET", ""),
		JWTAccessTTL:      parseDuration("JWT_ACCESS_TTL", 15*time.Minute),
		JWTRefreshTTL:     parseDuration("JWT_REFRESH_TTL", 720*time.Hour),
		LogLevel:          getEnv("LOG_LEVEL", "info"),
		Env:               getEnv("ENV", "dev"),
		CORSOrigins:       getEnv("CORS_ORIGINS", ""),
		FCMProjectID:      getEnv("FCM_PROJECT_ID", ""),
		FCMServiceAccount: getEnv("FCM_SERVICE_ACCOUNT_JSON", ""),
		GameEpochDate:     getEnv("GAME_EPOCH_DATE", "2025-01-01"),

		KavenegarAPIKey:      getEnv("KAVENEGAR_API_KEY", ""),
		KavenegarOTPTemplate: getEnv("KAVENEGAR_OTP_TEMPLATE", "wordchain-otp"),
		OTPCodeTTL:           parseDuration("OTP_CODE_TTL", 2*time.Minute),
		OTPResendCooldown:    parseDuration("OTP_RESEND_COOLDOWN", 120*time.Second),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func parseDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}

// AITrapLetters are the Persian letters that the fewest fa.txt words start
// with (ژ 26, ظ 28, ث 38, ذ 46, ض 54 words of ≥3 letters). Ending a word on
// one leaves the opponent few follow-ups — the AI prefers them when TrapPref
// fires. ی is deliberately excluded: few words start with it but ~2.6k end
// with it, so it would make the hard AI trap constantly. Keep in sync with
// Flutter's `aiTrapLetters` (client/lib/core/services/ai_opponent.dart).
var AITrapLetters = map[rune]bool{'ژ': true, 'ظ': true, 'ث': true, 'ذ': true, 'ض': true}

// AIDifficulty holds the configuration for one AI skill level.
type AIDifficulty struct {
	DelayMs       int     // milliseconds before the AI submits its word
	MistakeRate   float64 // probability [0,1] of submitting an intentionally invalid word
	MinWordLength int     // minimum word length the AI will choose
	TrapPref      float64 // probability [0,1] of choosing a trap-ending word
	PreferLongest bool    // when TrapPref fires, pick the longest trap word
}

// AIDifficulties maps difficulty names to their configs per the game spec.
var AIDifficulties = map[string]AIDifficulty{
	"easy": {
		DelayMs:       3000,
		MistakeRate:   0.25,
		MinWordLength: 3,
		TrapPref:      0,
		PreferLongest: false,
	},
	"medium": {
		DelayMs:       1500,
		MistakeRate:   0.10,
		MinWordLength: 4,
		TrapPref:      0.30,
		PreferLongest: false,
	},
	"hard": {
		DelayMs:       600,
		MistakeRate:   0.02,
		MinWordLength: 6,
		TrapPref:      0.70,
		PreferLongest: true,
	},
}

// Game tuning defaults — read from this package in handlers and services.
// Change values here; never scatter magic numbers elsewhere.
const (
	TurnTimerClassicSec = 15  // seconds per turn in Classic mode
	EntryFeeCoins       = 20  // coins each human player pays to start a 1v1 match; the winner takes the 2× pot
	RoomWaitTimeoutSec  = 120 // a room whose second player never joins is cancelled and removed after this long
	MinWordLength       = 3   // minimum accepted word length
	ContinueWindowSec   = 15  // seconds the losing player has to decide on a continue
	MaxDailyWords       = 20  // word limit for Daily Challenge
	ContinueCoins       = 25  // coins spent to continue (Classic)
	DailyRetryCoins     = 25  // coins spent to retry Daily Challenge
	HintSessionLimit    = 5   // free hint uses per guest session
	AIFallbackWaitSec   = 30  // matchmaking waits this long before pairing with AI
	OTPMaxAttempts      = 5   // failed verify-otp attempts allowed before lockout
	OTPMaxSendsPerDay   = 10  // send-otp requests allowed per phone per rolling day

	// SystemAIUserID is the fixed, well-known users.id row for the matchmaking
	// AI-fallback opponent (backend/internal/service/matchmaking.go). A single
	// shared identity is used regardless of difficulty — difficulty only
	// affects in-memory AI behavior (internal/ws/ai_client.go) and is never
	// persisted per-player. Seeded by migration 004_ai_system_user.
	SystemAIUserID = "00000000-0000-0000-0000-000000000001"

	// Coin rewards
	CoinWinMatch        = 30
	CoinDailyLogin      = 10
	CoinRewardedAd      = 20
	CoinMatchStreak5    = 15
	CoinDailyStreak3    = 30
	CoinDailyStreak7    = 100
	CoinDailyStreak30   = 500
	CoinWeeklyRank1     = 500
	CoinWeeklyRank2     = 300
	CoinWeeklyRank3     = 100
	CoinReferralSignup  = 100 // new user, valid referral code supplied at signup
	CoinReferralRedeem  = 50  // existing user, one-time post-login referral redemption
	CoinDailyComplete   = 10  // finishing the day's Daily Challenge
	CoinDailyRank1      = 100 // Daily Challenge top 3 of the day (paid at Iran midnight)
	CoinDailyRank2      = 60
	CoinDailyRank3      = 30
	CoinWelcome         = 50 // flat bonus for every new account, credited at signup
	CoinReferralInviter = 50 // referrer, per invited user; claimed from the inbox

	// Power-up costs
	CoinHint      = 10
	CoinFreeze    = 20
	CoinExtraTime = 15
	CoinShield    = 20 // not in the original spec's price list; priced between Extra Time and Freeze
)

// Premium perks. Taunts are preset messages only (never free text): the client
// sends an ID and the server broadcasts it. Keep TauntIDs/AvatarIDs in sync with
// GameConstants.tauntIds / premiumAvatarIds in the Flutter client.
const (
	TauntCooldownSec = 5 // minimum gap between one player's taunts
	TauntMaxPerMatch = 8 // taunts one player may send in a single match
)

// TauntIDs is the whitelist of sendable taunts (Persian text lives client-side).
var TauntIDs = map[string]bool{
	"what_happened": true,
	"hurry_up":      true,
	"your_turn":     true,
	"thinking":      true,
	"too_easy":      true,
	"lucky":         true,
	"nice_one":      true,
	"good_game":     true,
	"oops":          true,
}

// AvatarIDs is the premium avatar catalogue (glyph/colour art lives client-side).
var AvatarIDs = map[string]bool{
	"lion": true, "simorgh": true, "falcon": true, "fox": true,
	"owl": true, "cat": true, "horse": true, "dragon": true,
	"crown": true, "pen": true, "flame": true, "moon": true,
	"star": true, "diamond": true, "bolt": true, "rose": true,
}

// RewardClaimedRetention is how long a claimed reward stays listed on the rewards screen.
const RewardClaimedRetention = 24 * time.Hour

// PowerupPrice returns the coin cost of one use of a power-up when the player's
// inventory is empty, and false for an unknown type.
func PowerupPrice(powerupType string) (int, bool) {
	switch powerupType {
	case "hint":
		return CoinHint, true
	case "freeze":
		return CoinFreeze, true
	case "extra_time":
		return CoinExtraTime, true
	case "shield":
		return CoinShield, true
	}
	return 0, false
}

// XP / level curve. Reaching level L costs LevelXPStep * L * (L-1) / 2 total XP,
// i.e. the step from level L to L+1 is LevelXPStep * L (level 2 at 1000 XP,
// level 3 at 3000, level 4 at 6000, ...). A game's XP is its score.
const LevelXPStep = 1000

// XPForLevel returns the cumulative XP needed to reach the given level (1-based).
func XPForLevel(level int) int64 {
	if level <= 1 {
		return 0
	}
	return int64(LevelXPStep) * int64(level) * int64(level-1) / 2
}

// LevelFromXP returns the level (>=1) for a lifetime XP total.
func LevelFromXP(xp int64) int {
	level := 1
	for XPForLevel(level+1) <= xp {
		level++
	}
	return level
}
