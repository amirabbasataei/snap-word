package service

import (
	"context"
	"fmt"
	"log/slog"
	"math"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// RatingReasonPairCap marks a rated-looking match that changed nothing because
// the two players already had their rated games against each other today.
const RatingReasonPairCap = "pair_cap"

// WeeklyRatingBoard receives the net rating change of each newly applied match
// for the weekly board. Implemented by LeaderboardService.
type WeeklyRatingBoard interface {
	RecordRatedGame(ctx context.Context, winnerID, loserID string, winnerDelta, loserDelta int) error
}

// RatingService applies the Elo rating («جام») after 1v1 human games.
type RatingService struct {
	repo  *repository.RatingRepository
	board WeeklyRatingBoard // nil: no weekly board update (tests)
	now   func() time.Time
}

func NewRatingService(repo *repository.RatingRepository, board WeeklyRatingBoard) *RatingService {
	return &RatingService{repo: repo, board: board, now: time.Now}
}

// MatchRating is the outcome of one match for the rating.
type MatchRating struct {
	// Rated is false when the pair cap swallowed the match (Reason pair_cap);
	// Changes then carry the unchanged ratings with Delta 0.
	Rated   bool
	Reason  string
	Changes map[string]repository.RatingChange
}

// EloExpected is the expected score of a player rated ra against one rated rb.
func EloExpected(ra, rb int) float64 {
	return 1 / (1 + math.Pow(10, float64(rb-ra)/400))
}

// EloK is the K-factor for a player with ratedGames rated games behind them.
func EloK(ratedGames int) int {
	if ratedGames < config.RatingProvisionalGames {
		return config.RatingKProvisional
	}
	return config.RatingKStable
}

// EloUpdate returns both players' ratings after the winner beat the loser.
// Each delta comes from the pre-match ratings and the player's own K; a rating
// never drops below config.RatingFloor.
func EloUpdate(winner, loser repository.PlayerRating) (winnerAfter, loserAfter int) {
	dw := int(math.Round(float64(EloK(winner.RatedGames)) * (1 - EloExpected(winner.Rating, loser.Rating))))
	dl := int(math.Round(float64(EloK(loser.RatedGames)) * (0 - EloExpected(loser.Rating, winner.Rating))))
	return max(config.RatingFloor, winner.Rating+dw), max(config.RatingFloor, loser.Rating+dl)
}

// iranDayBounds returns [start, end) of the Iran calendar day containing t.
func iranDayBounds(t time.Time) (time.Time, time.Time) {
	l := t.In(config.IranLocation)
	start := time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, config.IranLocation)
	return start, start.AddDate(0, 0, 1)
}

// IsRatedPair reports whether a finished match between winner and loser can be
// rated: two different humans and a winner (draws, AI games are unrated).
func IsRatedPair(winnerID, loserID string) bool {
	return winnerID != "" && loserID != "" && winnerID != loserID &&
		winnerID != config.SystemAIUserID && loserID != config.SystemAIUserID
}

// ApplyMatchResult rates a finished 1v1 match. It returns nil for a match that
// is never rated (draw, AI). Applying the same match twice changes nothing and
// returns the stored result. The weekly board is fed only by the first apply.
func (s *RatingService) ApplyMatchResult(ctx context.Context, matchID, winnerID, loserID string) (*MatchRating, error) {
	if !IsRatedPair(winnerID, loserID) {
		return nil, nil
	}
	dayStart, dayEnd := iranDayBounds(s.now())
	res, err := s.repo.ApplyMatch(ctx, matchID, winnerID, loserID, dayStart, dayEnd,
		config.RatingPairCapPerDay, EloUpdate)
	if err != nil {
		return nil, fmt.Errorf("RatingService.ApplyMatchResult: %w", err)
	}
	out := &MatchRating{
		Rated:   !res.Capped,
		Changes: map[string]repository.RatingChange{winnerID: res.Winner, loserID: res.Loser},
	}
	if res.Capped {
		out.Reason = RatingReasonPairCap
		slog.Info("rating: pair cap reached, match unrated", "match", matchID, "winner", winnerID, "loser", loserID)
		return out, nil
	}
	if res.Applied && s.board != nil {
		if err := s.board.RecordRatedGame(ctx, winnerID, loserID, res.Winner.Delta, res.Loser.Delta); err != nil {
			// The rating itself is committed; only this week's board misses the game.
			slog.Error("rating: weekly board update failed", "match", matchID, "error", err)
		}
	}
	return out, nil
}

// RatingsOf returns each player's current rating (RatingStart for players with
// no stats row yet).
func (s *RatingService) RatingsOf(ctx context.Context, userIDs []string) (map[string]int, error) {
	rows, err := s.repo.GetRatings(ctx, userIDs)
	if err != nil {
		return nil, fmt.Errorf("RatingService.RatingsOf: %w", err)
	}
	out := make(map[string]int, len(userIDs))
	for _, id := range userIDs {
		if r, ok := rows[id]; ok {
			out[id] = r.Rating
		} else {
			out[id] = config.RatingStart
		}
	}
	return out, nil
}
