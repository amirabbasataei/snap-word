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

// Game tuning defaults — read from this package in handlers and services.
// Change values here; never scatter magic numbers elsewhere.
const (
	TurnTimerClassicSec    = 15  // seconds per turn in Classic mode
	TurnTimerTimeAttackSec = 8   // seconds per turn in Time Attack
	TimeAttackMatchSec     = 90  // total Time Attack match duration
	MinWordLength          = 3   // minimum accepted word length
	ContinueWindowSec      = 15  // seconds the losing player has to decide on a continue
	MaxDailyWords          = 20  // word limit for Daily Challenge
	ContinueCoins          = 25  // coins spent to continue (Classic)
	DailyRetryCoins        = 25  // coins spent to retry Daily Challenge
	HintSessionLimit       = 5   // free hint uses per guest session
	AIFallbackWaitSec      = 30  // matchmaking waits this long before pairing with AI

	// Coin rewards
	CoinWinMatch         = 30
	CoinDailyLogin       = 10
	CoinRewardedAd       = 20
	CoinMatchStreak5     = 15
	CoinDailyStreak3     = 30
	CoinDailyStreak7     = 100
	CoinDailyStreak30    = 500
	CoinWeeklyRank1      = 500
	CoinWeeklyRank2      = 300
	CoinWeeklyRank3      = 100

	// Power-up costs
	CoinHint      = 10
	CoinFreeze    = 20
	CoinExtraTime = 15
)
