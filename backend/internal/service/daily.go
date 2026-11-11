package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

var (
	ErrNoDailyChallenge    = errors.New("no_daily_challenge")
	ErrDailyNotAttempted   = errors.New("not_attempted")
	ErrDailyAlreadyRetried = errors.New("already_retried")
	// ErrInvalidDailyVariant: a variant outside 1..config.DailyVariantMax.
	ErrInvalidDailyVariant = errors.New("invalid_daily_variant")
)

type DailyAttemptInfo struct {
	AttemptNumber int
	Score         int
	ChainLength   int
	WordChain     []string
}

type DailyInfo struct {
	ChallengeDate string
	DayNumber     int
	Variant       int    // the link position this info is about (1 = classic)
	StartLetter   string // the letter the first word carries at position Variant
	TurnTimerSec  int
	// PlayedVariants are the variants the caller has a free attempt at today,
	// ascending — the type picker marks them.
	PlayedVariants []int
	TodayBest      int // top free-attempt score of the day (the board's first row)
	YourBest       int // the caller's best over both attempts (a paid retry counts here)
	DailyStreak    int
	Attempt        *DailyAttemptInfo
	RetryAttempt   *DailyAttemptInfo
	Rank           *int // by the free attempt only; a paid retry never changes it
}

type DailyService struct {
	dailyRepo *repository.DailyRepository
	statsRepo *repository.StatsRepository
	userRepo  *repository.UserRepository
	notifSvc  *NotificationService
	epoch     time.Time
}

func NewDailyService(
	dailyRepo *repository.DailyRepository,
	statsRepo *repository.StatsRepository,
	userRepo *repository.UserRepository,
	notifSvc *NotificationService,
	cfg *config.Config,
) (*DailyService, error) {
	epoch, err := time.Parse("2006-01-02", cfg.GameEpochDate)
	if err != nil {
		return nil, fmt.Errorf("parse GAME_EPOCH_DATE: %w", err)
	}
	return &DailyService{
		dailyRepo: dailyRepo,
		statsRepo: statsRepo,
		userRepo:  userRepo,
		notifSvc:  notifSvc,
		epoch:     epoch,
	}, nil
}

func (s *DailyService) GetDailyInfo(ctx context.Context, userID string, variant int) (*DailyInfo, error) {
	if !config.IsDailyVariant(variant) {
		return nil, ErrInvalidDailyVariant
	}
	today := todayIran()

	ch, err := s.dailyRepo.GetChallenge(ctx, today)
	if errors.Is(err, repository.ErrNoDailyChallenge) {
		return nil, ErrNoDailyChallenge
	}
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	dayNumber := int(today.Sub(s.epoch).Hours()/24) + 1

	todayBest, err := s.dailyRepo.GetTodayBest(ctx, today, variant)
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	attempts, err := s.dailyRepo.GetUserAttempts(ctx, userID, today, variant)
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	played, err := s.dailyRepo.PlayedVariants(ctx, userID, today)
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	var rank *int
	if len(attempts) > 0 {
		rank, err = s.dailyRepo.GetUserRank(ctx, today, variant, userID)
		if err != nil {
			return nil, fmt.Errorf("GetDailyInfo: %w", err)
		}
	}

	dailyStreak := 0
	stats, err := s.statsRepo.GetStats(ctx, userID)
	if err == nil {
		dailyStreak = stats.DailyStreak
	}

	info := &DailyInfo{
		ChallengeDate:  today.Format("2006-01-02"),
		DayNumber:      dayNumber,
		Variant:        variant,
		StartLetter:    engine.DailyVariantStartLetter(ch.StartLetter, ch.Seed, variant),
		TurnTimerSec:   config.DailyTurnTimerSec(variant),
		PlayedVariants: played,
		TodayBest:      todayBest,
		DailyStreak:    dailyStreak,
		Rank:           rank,
	}

	yourBest := 0
	for _, a := range attempts {
		ai := toAttemptInfo(a)
		if a.AttemptNumber == 1 {
			info.Attempt = ai
		} else if a.AttemptNumber == 2 {
			info.RetryAttempt = ai
		}
		if a.Score > yourBest {
			yourBest = a.Score
		}
	}
	info.YourBest = yourBest

	return info, nil
}

// Retry deducts DailyRetryCoins from the user's balance for a second attempt
// at one variant. Returns an error if the user has not yet played that variant
// today or has already used its retry.
func (s *DailyService) Retry(ctx context.Context, userID string, variant int) error {
	if !config.IsDailyVariant(variant) {
		return ErrInvalidDailyVariant
	}
	today := todayIran()

	attempts, err := s.dailyRepo.GetUserAttempts(ctx, userID, today, variant)
	if err != nil {
		return fmt.Errorf("Retry: %w", err)
	}

	hasFirst := false
	for _, a := range attempts {
		if a.AttemptNumber == 1 {
			hasFirst = true
		}
		if a.AttemptNumber == 2 {
			return ErrDailyAlreadyRetried
		}
	}
	if !hasFirst {
		return ErrDailyNotAttempted
	}

	fresh, err := s.dailyRepo.RecordRetry(ctx, userID, today, variant)
	if err != nil {
		return fmt.Errorf("Retry: %w", err)
	}
	if !fresh {
		return ErrDailyAlreadyRetried
	}
	if err := s.userRepo.SpendCoins(ctx, userID, config.DailyRetryCoins); err != nil {
		if delErr := s.dailyRepo.DeleteRetry(ctx, userID, today, variant); delErr != nil {
			slog.Error("Retry: rollback failed", "userID", userID, "error", delErr)
		}
		return err
	}
	return nil
}

// EnsureChallenge generates and stores a daily_challenges row for date if one
// doesn't already exist. The seed is derived from date, so a row regenerated
// after being manually deleted comes back with the same start letter.
func (s *DailyService) EnsureChallenge(ctx context.Context, date time.Time) error {
	seed := date.Unix()
	startLetter := engine.PickDailyStartLetter(seed)
	if _, err := s.dailyRepo.CreateChallengeIfMissing(ctx, date, seed, startLetter); err != nil {
		return fmt.Errorf("EnsureChallenge: %w", err)
	}
	return nil
}

func toAttemptInfo(a *repository.DailyAttemptRow) *DailyAttemptInfo {
	return &DailyAttemptInfo{
		AttemptNumber: a.AttemptNumber,
		Score:         a.Score,
		ChainLength:   a.ChainLength,
		WordChain:     a.WordChain,
	}
}

// todayIran is the current Iran calendar day — the Daily Challenge day.
func todayIran() time.Time {
	return config.IranDate(time.Now())
}

// DailyBoard is today's ranking of one Daily Challenge variant.
type DailyBoard struct {
	ChallengeDate string
	DayNumber     int
	Variant       int
	Entries       []*repository.DailyBoardRow
	MyRank        *int
}

// Leaderboard returns today's ranking of one variant (each player's free
// attempt) and the caller's own rank on it.
func (s *DailyService) Leaderboard(ctx context.Context, userID string, variant, limit int) (*DailyBoard, error) {
	if !config.IsDailyVariant(variant) {
		return nil, ErrInvalidDailyVariant
	}
	today := todayIran()
	entries, err := s.dailyRepo.GetDailyLeaderboard(ctx, today, variant, limit)
	if err != nil {
		return nil, fmt.Errorf("Leaderboard: %w", err)
	}
	rank, err := s.dailyRepo.GetUserRank(ctx, today, variant, userID)
	if err != nil {
		return nil, fmt.Errorf("Leaderboard: %w", err)
	}
	return &DailyBoard{
		ChallengeDate: today.Format("2006-01-02"),
		DayNumber:     int(today.Sub(s.epoch).Hours()/24) + 1,
		Variant:       variant,
		Entries:       entries,
		MyRank:        rank,
	}, nil
}

// DailyRewardRef is the inbox_rewards ref of a Daily payout: the date for
// the classic variant (as before variants existed, so a re-run never pays a
// day twice), the date plus "/v<N>" for the others.
func DailyRewardRef(date time.Time, variant int) string {
	ref := date.Format("2006-01-02")
	if variant != config.DailyVariantClassic {
		ref += "/v" + strconv.Itoa(variant)
	}
	return ref
}

// DailyVariantFromRef is the variant a Daily payout ref (DailyRewardRef)
// belongs to: N for "date/vN", classic for a bare date or anything else.
func DailyVariantFromRef(ref string) int {
	_, v, ok := strings.Cut(ref, "/v")
	if !ok {
		return config.DailyVariantClassic
	}
	n, err := strconv.Atoi(v)
	if err != nil || !config.IsDailyVariant(n) {
		return config.DailyVariantClassic
	}
	return n
}

// dailyVariantTitle names a harder variant in push text («حرف دوم»); empty for
// the classic one.
func dailyVariantTitle(variant int) string {
	switch variant {
	case 2:
		return "حرف دوم"
	case 3:
		return "حرف سوم"
	}
	return ""
}

// RunDailyPayout pays the prizes for a finished challenge day (called after
// Iran midnight), separately for every variant: each finisher of a variant
// gets its completion prize, the top 3 of each variant an extra rank prize.
// Ranks come from the free attempt only — a paid retry can not buy a better
// one. All are claimable inbox messages, idempotent per (user, kind, ref), so
// re-running is safe.
func (s *DailyService) RunDailyPayout(ctx context.Context, date time.Time) error {
	var firstErr error
	players := 0
	for v := config.DailyVariantClassic; v <= config.DailyVariantMax; v++ {
		n, err := s.payoutVariant(ctx, date, v)
		players += n
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if firstErr != nil {
		return fmt.Errorf("RunDailyPayout: %w", firstErr)
	}
	slog.Info("daily payout complete", "date", date.Format("2006-01-02"), "players", players)
	return nil
}

func (s *DailyService) payoutVariant(ctx context.Context, date time.Time, variant int) (int, error) {
	rows, err := s.dailyRepo.GetDailyLeaderboard(ctx, date, variant, 1<<30)
	if err != nil {
		return 0, fmt.Errorf("payoutVariant %d: %w", variant, err)
	}
	ref := DailyRewardRef(date, variant)
	rankCoins := map[int]int{1: config.CoinDailyRank1, 2: config.CoinDailyRank2, 3: config.CoinDailyRank3}
	doneTitle, rankTitle := "چالش روزانه تموم شد", "جایزه چالش روزانه"
	if t := dailyVariantTitle(variant); t != "" {
		doneTitle, rankTitle = doneTitle+"، "+t, rankTitle+"، "+t
	}

	var firstErr error
	award := func(userID, kind, detail string, coins int, title, body string) {
		created, err := s.userRepo.CreateInboxReward(ctx, userID, kind, ref, detail, coins)
		if err != nil {
			slog.Error("daily payout: CreateInboxReward failed", "userID", userID, "kind", kind, "variant", variant, "error", err)
			if firstErr == nil {
				firstErr = err
			}
			return
		}
		if created {
			_ = s.notifSvc.SendToUser(ctx, userID, title, body)
		}
	}

	for _, row := range rows {
		award(row.UserID, repository.RewardDailyDone, "", config.CoinDailyComplete, doneTitle,
			fmt.Sprintf("%s سکه گرفتی، از صندوق جایزه‌ها بردارش.", faNum(config.CoinDailyComplete)))
		if coins, ok := rankCoins[row.Rank]; ok {
			award(row.UserID, repository.RewardDailyRank, strconv.Itoa(row.Rank), coins, rankTitle,
				fmt.Sprintf("در چالش دیروز نفر %s شدی و %s سکه گرفتی! از صندوق جایزه‌ها بردارش.", faNum(row.Rank), faNum(coins)))
		}
	}
	return len(rows), firstErr
}
