package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

var (
	ErrNoDailyChallenge    = errors.New("no_daily_challenge")
	ErrDailyNotAttempted   = errors.New("not_attempted")
	ErrDailyAlreadyRetried = errors.New("already_retried")
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
	StartLetter   string
	TodayBest     int
	YourBest      int
	DailyStreak   int
	Attempt       *DailyAttemptInfo
	RetryAttempt  *DailyAttemptInfo
	Rank          *int
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

func (s *DailyService) GetDailyInfo(ctx context.Context, userID string) (*DailyInfo, error) {
	today := todayIran()

	ch, err := s.dailyRepo.GetChallenge(ctx, today)
	if errors.Is(err, repository.ErrNoDailyChallenge) {
		return nil, ErrNoDailyChallenge
	}
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	dayNumber := int(today.Sub(s.epoch).Hours()/24) + 1

	todayBest, err := s.dailyRepo.GetTodayBest(ctx, today)
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	attempts, err := s.dailyRepo.GetUserAttempts(ctx, userID, today)
	if err != nil {
		return nil, fmt.Errorf("GetDailyInfo: %w", err)
	}

	var rank *int
	if len(attempts) > 0 {
		rank, err = s.dailyRepo.GetUserRank(ctx, today, userID)
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
		ChallengeDate: today.Format("2006-01-02"),
		DayNumber:     dayNumber,
		StartLetter:   ch.StartLetter,
		TodayBest:     todayBest,
		DailyStreak:   dailyStreak,
		Rank:          rank,
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

// Retry deducts DailyRetryCoins from the user's balance. Returns an error if the
// user has not yet played today or has already used their retry.
func (s *DailyService) Retry(ctx context.Context, userID string) error {
	today := todayIran()

	attempts, err := s.dailyRepo.GetUserAttempts(ctx, userID, today)
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

	fresh, err := s.dailyRepo.RecordRetry(ctx, userID, today)
	if err != nil {
		return fmt.Errorf("Retry: %w", err)
	}
	if !fresh {
		return ErrDailyAlreadyRetried
	}
	if err := s.userRepo.SpendCoins(ctx, userID, config.DailyRetryCoins); err != nil {
		if delErr := s.dailyRepo.DeleteRetry(ctx, userID, today); delErr != nil {
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

// DailyBoard is today's Daily Challenge ranking.
type DailyBoard struct {
	ChallengeDate string
	DayNumber     int
	Entries       []*repository.DailyBoardRow
	MyRank        *int
}

// Leaderboard returns today's ranking (best score per player) and the
// caller's own rank.
func (s *DailyService) Leaderboard(ctx context.Context, userID string, limit int) (*DailyBoard, error) {
	today := todayIran()
	entries, err := s.dailyRepo.GetDailyLeaderboard(ctx, today, limit)
	if err != nil {
		return nil, fmt.Errorf("Leaderboard: %w", err)
	}
	rank, err := s.dailyRepo.GetUserRank(ctx, today, userID)
	if err != nil {
		return nil, fmt.Errorf("Leaderboard: %w", err)
	}
	return &DailyBoard{
		ChallengeDate: today.Format("2006-01-02"),
		DayNumber:     int(today.Sub(s.epoch).Hours()/24) + 1,
		Entries:       entries,
		MyRank:        rank,
	}, nil
}

// RunDailyPayout pays the prizes for a finished challenge day (called after
// Iran midnight): every finisher gets the completion prize, the top 3 an
// extra rank prize. Both are claimable inbox messages, idempotent per
// (user, kind, date), so re-running is safe.
func (s *DailyService) RunDailyPayout(ctx context.Context, date time.Time) error {
	rows, err := s.dailyRepo.GetDailyLeaderboard(ctx, date, 1<<30)
	if err != nil {
		return fmt.Errorf("RunDailyPayout: %w", err)
	}
	dateStr := date.Format("2006-01-02")
	rankCoins := map[int]int{1: config.CoinDailyRank1, 2: config.CoinDailyRank2, 3: config.CoinDailyRank3}

	var firstErr error
	award := func(userID, kind, detail string, coins int, title, body string) {
		created, err := s.userRepo.CreateInboxReward(ctx, userID, kind, dateStr, detail, coins)
		if err != nil {
			slog.Error("daily payout: CreateInboxReward failed", "userID", userID, "kind", kind, "error", err)
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
		award(row.UserID, repository.RewardDailyDone, "", config.CoinDailyComplete,
			"Daily Challenge complete",
			fmt.Sprintf("You earned %d coins — claim them in your inbox.", config.CoinDailyComplete))
		if coins, ok := rankCoins[row.Rank]; ok {
			award(row.UserID, repository.RewardDailyRank, strconv.Itoa(row.Rank), coins,
				"Daily Challenge reward",
				fmt.Sprintf("You finished #%d today and earned %d coins — claim them in your inbox!", row.Rank, coins))
		}
	}
	if firstErr != nil {
		return fmt.Errorf("RunDailyPayout: %w", firstErr)
	}
	slog.Info("daily payout complete", "date", dateStr, "players", len(rows))
	return nil
}
