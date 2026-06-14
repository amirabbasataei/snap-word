package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrNoDailyChallenge   = errors.New("no_daily_challenge")
	ErrDailyNotAttempted  = errors.New("not_attempted")
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
	epoch     time.Time
}

func NewDailyService(
	dailyRepo *repository.DailyRepository,
	statsRepo *repository.StatsRepository,
	userRepo *repository.UserRepository,
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
		epoch:     epoch,
	}, nil
}

func (s *DailyService) GetDailyInfo(ctx context.Context, userID string) (*DailyInfo, error) {
	today := todayUTC()

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
	today := todayUTC()

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

	if err := s.userRepo.SpendCoins(ctx, userID, config.DailyRetryCoins); err != nil {
		return err
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

func todayUTC() time.Time {
	now := time.Now().UTC()
	return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
}
