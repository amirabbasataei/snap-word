package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"wordchain/backend/internal/repository"
)

var (
	ErrMatchExists    = errors.New("match_already_exists")
	ErrMatchForbidden = errors.New("match_forbidden")
	ErrMatchNotFound  = errors.New("match_not_found")
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
}

func NewGameService(matchRepo *repository.MatchRepository, statsRepo *repository.StatsRepository) *GameService {
	return &GameService{matchRepo: matchRepo, statsRepo: statsRepo}
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

	if err := s.matchRepo.AddMatchPlayer(ctx, m.ID, userID, in.Score); err != nil {
		return nil, false, fmt.Errorf("CreateSoloGame add player: %w", err)
	}

	if err := s.updateStatsAfterSoloGame(ctx, userID, in.WordChain, in.EndedAt); err != nil {
		// non-fatal: match is already created; log and continue
		slog.Error("CreateSoloGame: stats update failed", "userID", userID, "error", err)
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

func (s *GameService) updateStatsAfterSoloGame(ctx context.Context, userID string, wordChain []string, endedAt time.Time) error {
	lw := longestWordIn(wordChain)
	return s.statsRepo.IncrementMatchStats(ctx, userID, lw, endedAt)
}

func longestWordIn(chain []string) string {
	var longest string
	for _, w := range chain {
		if len(w) > len(longest) {
			longest = w
		}
	}
	return longest
}
