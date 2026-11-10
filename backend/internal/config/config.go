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
	AdminAPIKey       string        // X-Admin-Key for scripts; the panel itself is enabled by having an admin user
	AdminSessionTTL   time.Duration // idle timeout of an admin panel session (sliding)
	AdminIPAllowlist  string        // comma-separated IPs/CIDRs allowed to reach /api/v1/admin; empty = anyone

	KavenegarAPIKey      string
	KavenegarOTPTemplate string
	OTPCodeTTL           time.Duration
	OTPResendCooldown    time.Duration

	// Cafe Bazaar purchase verification. Bazaar signs every purchase with its
	// private key; the server checks the signature with the app's public RSA
	// key (Bazaar panel → in-app payments → RSA key). Payments are off until
	// the key is set.
	BazaarPackageName  string
	BazaarRSAPublicKey string
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
		AdminAPIKey:       getEnv("ADMIN_API_KEY", ""),
		AdminSessionTTL:   parseDuration("ADMIN_SESSION_TTL", AdminSessionIdleTTL),
		AdminIPAllowlist:  getEnv("ADMIN_IP_ALLOWLIST", ""),

		KavenegarAPIKey:      getEnv("KAVENEGAR_API_KEY", ""),
		KavenegarOTPTemplate: getEnv("KAVENEGAR_OTP_TEMPLATE", "wordchain-otp"),
		OTPCodeTTL:           parseDuration("OTP_CODE_TTL", 2*time.Minute),
		OTPResendCooldown:    parseDuration("OTP_RESEND_COOLDOWN", 120*time.Second),

		BazaarPackageName:  getEnv("BAZAAR_PACKAGE_NAME", "com.ataei.zanjir"),
		BazaarRSAPublicKey: getEnv("BAZAAR_RSA_PUBLIC_KEY", ""),
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
	LongWordBonusMinLen = 7   // Flutter-only scoring: words this long (letters) have their turn score multiplied by LongWordBonusMult
	LongWordBonusMult   = 2   // see LongWordBonusMinLen; the server uses both only to bound uploaded Daily scores
	EntryFeeCoins       = 20  // coins each human player pays to start a 1v1 match; the winner takes the 2× pot
	RoomWaitTimeoutSec  = 120 // a room whose second player never joins is cancelled and removed after this long
	MinWordLength       = 2   // minimum accepted word length (letters); AI levels have their own, higher minimums
	ContinueWindowSec   = 15  // seconds the losing player has to decide on a continue
	DailyChainSafetyCap = 200 // abuse backstop on an uploaded Daily Challenge chain; players have no word limit (lives end the game)
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
	CoinWordSuggestion  = 25 // first signed-in reporter of an approved missing word; claimed from the inbox

	// Power-up costs
	CoinHint      = 10
	CoinExtraTime = 15
	CoinShield    = 20 // not in the original spec's price list; priced above Extra Time
)

// Skill rating («جام», Phase 25 S2): Elo for 1v1 human games only. AI-fallback
// rooms, cancelled rooms and draws are unrated. See SCORING_PLAN.md § S2.
const (
	RatingStart            = 1000 // every player's first rating (player_stats default)
	RatingFloor            = 0    // a rating never drops below this
	RatingKProvisional     = 32   // K for a player's first RatingProvisionalGames rated games
	RatingKStable          = 16   // K afterwards
	RatingProvisionalGames = 30
	RatingPairCapPerDay    = 3   // rated games per pair of players per Iran day; later ones change nothing
	RatingMinGamesForBoard = 10  // rated games needed to appear on the all-time board
	WeeklyMinRatedGames    = 5   // rated games in the week needed for a weekly prize (plus a positive net Δ)
	WeeklyPrizeScanLimit   = 200 // weekly rows scanned for the 3 prize-eligible players
)

// Premium perks. Taunts are preset messages only (never free text): the client
// sends an ID and the server broadcasts it. The taunt and avatar catalogues live
// in the `taunts` / `avatars` tables and are managed via the admin API.
const (
	TauntCooldownSec  = 5         // minimum gap between one player's taunts
	TauntMaxPerMatch  = 8         // taunts one player may send in a single match
	TauntMaxTextRunes = 60        // longest taunt text an operator may add
	AvatarMaxBytes    = 256 << 10 // largest avatar image an operator may upload
)

// Admin panel sessions and login throttling (Phase 23). The idle TTL is the
// ADMIN_SESSION_TTL default; the absolute cap is fixed.
const (
	AdminSessionIdleTTL     = 2 * time.Hour
	AdminSessionAbsoluteTTL = 12 * time.Hour
	AdminLoginMaxFailsIP    = 5  // failed logins per IP per window
	AdminLoginMaxFailsUser  = 10 // failed logins per username per window (stops guessing spread over many IPs)
	AdminLoginWindow        = 15 * time.Minute
	AdminPasswordMinLength  = 10
	AdminCookieName         = "zanjir_admin"
	AdminCSRFHeaderValue    = "zanjir-admin" // required in X-Requested-With on mutating cookie-authenticated requests
)

// Product analytics ingest limits (POST /api/v1/analytics/events, public).
const (
	AnalyticsMaxBatch             = 100                // events accepted in one request
	AnalyticsMaxBodyBytes         = 256 << 10          // request body cap
	AnalyticsMaxPropsBytes        = 1024               // serialized size cap of one event's props
	AnalyticsMaxPastSkew          = 7 * 24 * time.Hour // older client timestamps are replaced by the server's clock
	AnalyticsMaxFutureSkew        = 5 * time.Minute
	AnalyticsRatePerInstallPerMin = 30  // requests per install_id per minute
	AnalyticsRatePerIPPerMin      = 600 // requests per client IP per minute (mobile carriers NAT many players)
	AnalyticsRawRetentionMonths   = 6   // raw event partitions older than this are dropped; rollups are kept
	AnalyticsRollupLookbackDays   = 8   // the daily pass rebuilds this many past days (late offline uploads)
)

// Word suggestions (Phase 24): players report missing dictionary words or flag
// unreal / inappropriate ones; an admin decides.
const (
	WordSuggestMaxRunes      = 30   // longest word a player may report
	WordSuggestPerDay        = 10   // new reports per player (account or install) per Iran day
	WordSuggestPerIPPerDay   = 60   // per client IP per day (carriers NAT many players)
	WordMissesKeep           = 5000 // distinct multiplayer-rejected words kept in the Redis tally
	DictDeltaMaxRows         = 5000 // overrides returned by one GET /dictionary/delta call
	WordAdminBulkMax         = 100  // suggestions one bulk action may touch
	WordAdminPageSizeDefault = 50
	WordAdminPageSizeMax     = 200
)

// Admin notifications (stage A6): pushes and in-app messages sent from the panel.
const (
	NotifTitleMaxRunes   = 60  // push/message title
	NotifBodyMaxRunes    = 240 // push/message body
	NotifMaxTargetUsers  = 200 // accounts one "specific users" send may name
	NotifPushWorkers     = 8   // concurrent FCM requests while delivering a campaign
	NotifPushTimeout     = 15 * time.Minute
	NotifDuplicateWindow = 2 * time.Minute // an identical title+body inside this window is refused
	NotifPageSizeDefault = 20
	NotifPageSizeMax     = 100
	InboxMessageTTL      = 30 * 24 * time.Hour // unread in-app messages older than this are no longer shown
	InboxMessageListMax  = 50
)

// NotifRoutes are the deep links a push or in-app message may carry (the
// client's go_router paths); empty means "just open the app".
var NotifRoutes = []string{"/home", "/daily", "/friends", "/leaderboard", "/rewards", "/profile", "/messages"}

// RewardClaimedRetention is how long a claimed reward stays listed on the rewards screen.
const RewardClaimedRetention = 24 * time.Hour

// PowerupPrice returns the coin cost of one use of a power-up when the player's
// inventory is empty, and false for an unknown type.
func PowerupPrice(powerupType string) (int, bool) {
	switch powerupType {
	case "hint":
		return CoinHint, true
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

// StoreProductKind says what a store product delivers.
type StoreProductKind string

const (
	StoreProductCoins   StoreProductKind = "coins"
	StoreProductPremium StoreProductKind = "premium"
)

// StoreProduct is one SKU created in the Bazaar panel. The ids here must match
// the panel and the client (`GameConstants`/profile sheet). Prices live in the
// store, not here. «Remove ads» is deliberately absent: the app has no
// ad-free state yet, so it must not be sold.
type StoreProduct struct {
	ID    string
	Kind  StoreProductKind
	Coins int // StoreProductCoins only
}

// StoreProducts is the sellable catalogue.
var StoreProducts = map[string]StoreProduct{
	"coins_100":       {ID: "coins_100", Kind: StoreProductCoins, Coins: 100},
	"coins_350":       {ID: "coins_350", Kind: StoreProductCoins, Coins: 350},
	"coins_1500":      {ID: "coins_1500", Kind: StoreProductCoins, Coins: 1500},
	"premium_monthly": {ID: "premium_monthly", Kind: StoreProductPremium},
}

// PremiumPeriod is what one `premium_monthly` purchase is worth, counted from
// the purchase time in Bazaar's signed receipt.
const PremiumPeriod = 30 * 24 * time.Hour

// PremiumReverifyWindow keeps premium_until at least this far ahead of now each
// time the app re-reports a still-listed subscription. The signed receipt has
// no expiry (that needs the developer API), so this carries a renewal whose
// receipt still shows the old purchase time; a lapsed subscription stops being
// reported and premium ends once PremiumPeriod has passed.
const PremiumReverifyWindow = 72 * time.Hour

// StoreBazaar is the `store_purchases.store` value for Cafe Bazaar.
const StoreBazaar = "bazaar"
