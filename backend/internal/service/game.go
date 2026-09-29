package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"
	"unicode/utf8"

	"wordchain/backend/internal/repository"
)

var (
	ErrMatchExists    = errors.New("match_already_exists")
	ErrMatchForbidden = errors.New("match_forbidden")
	ErrMatchNotFound  = errors.New("match_not_found")
	// ErrDailyNotAllowed: today's free attempt (and any paid retry) is already used.
	ErrDailyNotAllowed = errors.New("daily_attempt_not_allowed")
)

// SoloGameInput is the payload sent by the Flutter SyncService for a completed solo game.
type SoloGameInput struct {
	Mode      string    `json:"mode"`
	Score     int       `json:"score"`
	WordChain []string  `json:"word_chain"`
	StartedAt time.Time `json:"started_at"`
	EndedAt   time.Time `json:"ended_at"`
}

// soloGameState is stored as JSONB in matches.game_state.
type soloGameState struct {
	WordChain []string `json:"word_chain"`
	Score     int      `json:"score"`
}

// MatchWithPlayers bundles a match and its player rows for API responses.
type MatchWithPlayers struct {
	Match   *repository.Match
	Players []*repository.MatchPlayer
}

// GameService handles game creation, retrieval, and stat updates.
type GameService struct {
	matchRepo *repository.MatchRepository
	statsRepo *repository.StatsRepository
	streakSvc *StreakService
	dailyRepo *repository.DailyRepository
}

func NewGameService(matchRepo *repository.MatchRepository, statsRepo *repository.StatsRepository, streakSvc *StreakService, dailyRepo *repository.DailyRepository) *GameService {
	return &GameService{matchRepo: matchRepo, statsRepo: statsRepo, streakSvc: streakSvc, dailyRepo: dailyRepo}
}

// dailyAttemptNumber decides which daily attempt slot an upload fills: 1 is
// the free attempt, 2 requires a paid retry. Returns ErrDailyNotAllowed when
// neither is available.
func (s *GameService) dailyAttemptNumber(ctx context.Context, userID string, date time.Time) (int, error) {
	attempts, err := s.dailyRepo.GetUserAttempts(ctx, userID, date)
	if err != nil {
		return 0, err
	}
	switch len(attempts) {
	case 0:
		return 1, nil
	case 1:
		paid, err := s.dailyRepo.HasRetry(ctx, userID, date)
		if err != nil {
			return 0, err
		}
		if paid {
			return 2, nil
		}
	}
	return 0, ErrDailyNotAllowed
}

// CreateSoloGame persists a finished solo match uploaded by the Flutter SyncService.
// alreadyExisted is true when a record with the same (userID, mode, startedAt) already exists —
// the handler should respond 409 in that case while still returning the existing match data
// so the Flutter can populate its remote ID.
func (s *GameService) CreateSoloGame(ctx context.Context, userID string, in SoloGameInput) (match *repository.Match, alreadyExisted bool, err error) {
	existing, err := s.matchRepo.FindSoloMatch(ctx, userID, in.Mode, in.StartedAt)
	if err == nil {
		return existing, true, nil
	}
	if !errors.Is(err, repository.ErrMatchNotFound) {
		return nil, false, fmt.Errorf("CreateSoloGame lookup: %w", err)
	}

	attemptNumber := 0
	var challengeDate time.Time
	if in.Mode == "daily" {
		d := in.StartedAt.UTC()
		challengeDate = time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, time.UTC)
		attemptNumber, err = s.dailyAttemptNumber(ctx, userID, challengeDate)
		if err != nil {
			return nil, false, fmt.Errorf("CreateSoloGame daily: %w", err)
		}
	}

	gs, err := json.Marshal(soloGameState{WordChain: in.WordChain, Score: in.Score})
	if err != nil {
		return nil, false, fmt.Errorf("CreateSoloGame marshal: %w", err)
	}

	startedAt := in.StartedAt
	endedAt := in.EndedAt
	winnerID := userID

	m, err := s.matchRepo.CreateMatch(ctx, in.Mode, "finished", &winnerID, gs, &startedAt, &endedAt)
	if err != nil {
		return nil, false, fmt.Errorf("CreateSoloGame: %w", err)
	}

	if err := s.matchRepo.AddMatchPlayer(ctx, m.ID, userID, in.Score, false); err != nil {
		return nil, false, fmt.Errorf("CreateSoloGame add player: %w", err)
	}

	if attemptNumber > 0 {
		if err := s.dailyRepo.InsertAttempt(ctx, userID, challengeDate, attemptNumber, in.Score, in.WordChain); err != nil {
			return nil, false, fmt.Errorf("CreateSoloGame daily attempt: %w", err)
		}
	}

	if err := s.updateStatsAfterSoloGame(ctx, userID, in.WordChain); err != nil {
		// non-fatal: match is already created; log and continue
		slog.Error("CreateSoloGame: stats update failed", "userID", userID, "error", err)
	}

	if s.streakSvc != nil {
		if err := s.streakSvc.RecordGamePlayed(ctx, userID, in.EndedAt); err != nil {
			slog.Error("CreateSoloGame: RecordGamePlayed failed", "userID", userID, "error", err)
		}
	}

	return m, false, nil
}

// GetGameState returns the match and its players. Returns ErrMatchForbidden if userID is not a player.
func (s *GameService) GetGameState(ctx context.Context, matchID, userID string) (*MatchWithPlayers, error) {
	match, err := s.matchRepo.GetMatch(ctx, matchID)
	if errors.Is(err, repository.ErrMatchNotFound) {
		return nil, ErrMatchNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("GetGameState: %w", err)
	}

	players, err := s.matchRepo.GetMatchPlayers(ctx, matchID)
	if err != nil {
		return nil, fmt.Errorf("GetGameState players: %w", err)
	}

	isPlayer := false
	for _, p := range players {
		if p.UserID == userID {
			isPlayer = true
			break
		}
	}
	if !isPlayer {
		return nil, ErrMatchForbidden
	}

	return &MatchWithPlayers{Match: match, Players: players}, nil
}

// GetStats returns the player's stats. When no stats row exists yet, zeroed stats are returned.
func (s *GameService) GetStats(ctx context.Context, userID string) (*repository.PlayerStats, error) {
	stats, err := s.statsRepo.GetStats(ctx, userID)
	if errors.Is(err, repository.ErrStatsNotFound) {
		return &repository.PlayerStats{UserID: userID}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("GetStats: %w", err)
	}
	return stats, nil
}

// EndGame marks a match as finished and sets the winner. Called by the WS room in Phase 8.
func (s *GameService) EndGame(ctx context.Context, matchID, winnerID string) error {
	if err := s.matchRepo.UpdateMatchStatus(ctx, matchID, "finished"); err != nil {
		return fmt.Errorf("EndGame: %w", err)
	}
	return nil
}

func (s *GameService) updateStatsAfterSoloGame(ctx context.Context, userID string, wordChain []string) error {
	return s.statsRepo.IncrementMatchStats(ctx, userID, longestWordIn(wordChain))
}

// longestWordIn compares by letters (runes), not bytes.
func longestWordIn(chain []string) string {
	var longest string
	longestLen := 0
	for _, w := range chain {
		if n := utf8.RuneCountInString(w); n > longestLen {
			longest, longestLen = w, n
		}
	}
	return longest
}
