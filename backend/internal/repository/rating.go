package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/lib/pq"
)

// RatingRepository persists the Elo rating (Phase 25 S2): player_stats.rating /
// rated_games / peak_rating and the rating_history ledger.
type RatingRepository struct {
	db *sql.DB
}

func NewRatingRepository(db *sql.DB) *RatingRepository {
	return &RatingRepository{db: db}
}

// PlayerRating is a player's rating state before a match.
type PlayerRating struct {
	Rating     int
	RatedGames int
	Peak       int
}

// RatingChange is one player's before/after for a match.
type RatingChange struct {
	UserID string
	Before int
	After  int
	Delta  int
}

// RatingApplyResult reports what ApplyMatch did.
type RatingApplyResult struct {
	// Applied is true only when this call wrote the result. A replay of an
	// already-applied match returns the stored changes with Applied false.
	Applied bool
	// Capped: the pair already had its rated games for the day, nothing changed
	// (Winner/Loser then carry the unchanged ratings with Delta 0).
	Capped bool
	Winner RatingChange
	Loser  RatingChange
}

// RatingCompute turns both players' pre-match state into their new ratings.
type RatingCompute func(winner, loser PlayerRating) (winnerAfter, loserAfter int)

// ApplyMatch applies a rated match in one transaction: it locks both
// player_stats rows (creating them if needed), returns the stored result if the
// match was already applied (rating_history primary key), skips the match when
// the pair already played pairCap rated games in [dayStart, dayEnd), and
// otherwise writes both history rows and the new ratings.
func (r *RatingRepository) ApplyMatch(ctx context.Context, matchID, winnerID, loserID string,
	dayStart, dayEnd time.Time, pairCap int, compute RatingCompute) (RatingApplyResult, error) {
	var res RatingApplyResult
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch begin: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	if _, err := tx.ExecContext(ctx,
		`INSERT INTO player_stats (user_id) VALUES ($1), ($2) ON CONFLICT (user_id) DO NOTHING`,
		winnerID, loserID); err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch ensure stats: %w", err)
	}

	// Lock in a fixed order so two concurrent matches of one pair cannot deadlock.
	rows, err := tx.QueryContext(ctx, `
		SELECT user_id, rating, rated_games, peak_rating FROM player_stats
		WHERE user_id = ANY($1::uuid[]) ORDER BY user_id FOR UPDATE`,
		pq.Array([]string{winnerID, loserID}))
	if err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch lock: %w", err)
	}
	state := map[string]PlayerRating{}
	for rows.Next() {
		var id string
		var p PlayerRating
		if err := rows.Scan(&id, &p.Rating, &p.RatedGames, &p.Peak); err != nil {
			rows.Close()
			return res, fmt.Errorf("RatingRepository.ApplyMatch scan: %w", err)
		}
		state[id] = p
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch rows: %w", err)
	}
	w, okW := state[winnerID]
	l, okL := state[loserID]
	if !okW || !okL {
		return res, fmt.Errorf("RatingRepository.ApplyMatch: player_stats rows missing")
	}

	// Replay: the history rows already exist.
	stored, err := matchChanges(ctx, tx, matchID)
	if err != nil {
		return res, err
	}
	if len(stored) > 0 {
		res.Winner, res.Loser = stored[winnerID], stored[loserID]
		return res, tx.Commit()
	}

	var pairGames int
	if err := tx.QueryRowContext(ctx, `
		SELECT count(*) FROM rating_history
		WHERE user_id = $1 AND opponent_id = $2 AND created_at >= $3 AND created_at < $4`,
		winnerID, loserID, dayStart, dayEnd).Scan(&pairGames); err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch pair count: %w", err)
	}
	if pairGames >= pairCap {
		res.Capped = true
		res.Winner = RatingChange{UserID: winnerID, Before: w.Rating, After: w.Rating}
		res.Loser = RatingChange{UserID: loserID, Before: l.Rating, After: l.Rating}
		return res, tx.Commit()
	}

	wAfter, lAfter := compute(w, l)
	res.Winner = RatingChange{UserID: winnerID, Before: w.Rating, After: wAfter, Delta: wAfter - w.Rating}
	res.Loser = RatingChange{UserID: loserID, Before: l.Rating, After: lAfter, Delta: lAfter - l.Rating}

	ins, err := tx.ExecContext(ctx, `
		INSERT INTO rating_history (match_id, user_id, opponent_id, rating_before, rating_after, delta)
		VALUES ($1, $2, $3, $4, $5, $6), ($1, $3, $2, $7, $8, $9)
		ON CONFLICT (match_id, user_id) DO NOTHING`,
		matchID, winnerID, loserID,
		res.Winner.Before, res.Winner.After, res.Winner.Delta,
		res.Loser.Before, res.Loser.After, res.Loser.Delta)
	if err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch history: %w", err)
	}
	if n, _ := ins.RowsAffected(); n != 2 {
		// Unreachable while both rows are locked above; never half-apply.
		return res, fmt.Errorf("RatingRepository.ApplyMatch: history conflict (%d rows)", n)
	}
	for _, c := range []RatingChange{res.Winner, res.Loser} {
		if _, err := tx.ExecContext(ctx, `
			UPDATE player_stats SET rating = $2, rated_games = rated_games + 1,
			       peak_rating = GREATEST(peak_rating, $2), updated_at = now()
			WHERE user_id = $1`, c.UserID, c.After); err != nil {
			return res, fmt.Errorf("RatingRepository.ApplyMatch update: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return res, fmt.Errorf("RatingRepository.ApplyMatch commit: %w", err)
	}
	res.Applied = true
	return res, nil
}

func matchChanges(ctx context.Context, q interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}, matchID string) (map[string]RatingChange, error) {
	rows, err := q.QueryContext(ctx,
		`SELECT user_id, rating_before, rating_after, delta FROM rating_history WHERE match_id = $1`, matchID)
	if err != nil {
		return nil, fmt.Errorf("RatingRepository.matchChanges: %w", err)
	}
	defer rows.Close()
	out := map[string]RatingChange{}
	for rows.Next() {
		var c RatingChange
		if err := rows.Scan(&c.UserID, &c.Before, &c.After, &c.Delta); err != nil {
			return nil, fmt.Errorf("RatingRepository.matchChanges scan: %w", err)
		}
		out[c.UserID] = c
	}
	return out, rows.Err()
}

// MatchChanges returns the stored rating changes of one match (empty when unrated).
func (r *RatingRepository) MatchChanges(ctx context.Context, matchID string) (map[string]RatingChange, error) {
	return matchChanges(ctx, r.db, matchID)
}

// RatingRow is a player's rating on a board.
type RatingRow struct {
	UserID     string
	Username   string
	Rating     int
	RatedGames int
	Peak       int
}

// GetRatings returns the rating state of the given players. Players without a
// player_stats row are absent (callers treat them as RatingStart / 0 games).
func (r *RatingRepository) GetRatings(ctx context.Context, userIDs []string) (map[string]RatingRow, error) {
	out := make(map[string]RatingRow, len(userIDs))
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT user_id, rating, rated_games, peak_rating FROM player_stats
		WHERE user_id = ANY($1::uuid[])`, pq.Array(userIDs))
	if err != nil {
		return nil, fmt.Errorf("RatingRepository.GetRatings: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var row RatingRow
		if err := rows.Scan(&row.UserID, &row.Rating, &row.RatedGames, &row.Peak); err != nil {
			return nil, fmt.Errorf("RatingRepository.GetRatings scan: %w", err)
		}
		out[row.UserID] = row
	}
	return out, rows.Err()
}

// TopRated is the all-time board: players with at least minGames rated games,
// highest rating first (ties: more rated games, then the older account). The
// excluded user (the AI) and banned accounts never appear.
func (r *RatingRepository) TopRated(ctx context.Context, n, minGames int, excludeUserID string) ([]RatingRow, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT ps.user_id, COALESCE(u.username, ''), ps.rating, ps.rated_games, ps.peak_rating
		FROM player_stats ps
		JOIN users u ON u.id = ps.user_id
		WHERE ps.rated_games >= $2 AND ps.user_id <> $3 AND u.banned_at IS NULL
		ORDER BY ps.rating DESC, ps.rated_games DESC, u.created_at ASC, ps.user_id ASC
		LIMIT $1`, n, minGames, excludeUserID)
	if err != nil {
		return nil, fmt.Errorf("RatingRepository.TopRated: %w", err)
	}
	defer rows.Close()
	var out []RatingRow
	for rows.Next() {
		var row RatingRow
		if err := rows.Scan(&row.UserID, &row.Username, &row.Rating, &row.RatedGames, &row.Peak); err != nil {
			return nil, fmt.Errorf("RatingRepository.TopRated scan: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// RatedRank returns the player's 1-indexed place on the all-time board (same
// order as TopRated), or 0 when they are not on it (too few rated games, or
// banned). The player's own row is returned either way (zero values if none).
func (r *RatingRepository) RatedRank(ctx context.Context, userID string, minGames int, excludeUserID string) (int64, RatingRow, error) {
	row := RatingRow{UserID: userID}
	var created time.Time
	var banned bool
	err := r.db.QueryRowContext(ctx, `
		SELECT ps.rating, ps.rated_games, ps.peak_rating, u.created_at, u.banned_at IS NOT NULL
		FROM player_stats ps JOIN users u ON u.id = ps.user_id
		WHERE ps.user_id = $1`, userID).Scan(&row.Rating, &row.RatedGames, &row.Peak, &created, &banned)
	if err == sql.ErrNoRows {
		return 0, row, nil
	}
	if err != nil {
		return 0, row, fmt.Errorf("RatingRepository.RatedRank: %w", err)
	}
	if row.RatedGames < minGames || banned || userID == excludeUserID {
		return 0, row, nil
	}
	var ahead int64
	if err := r.db.QueryRowContext(ctx, `
		SELECT count(*) FROM player_stats ps JOIN users u ON u.id = ps.user_id
		WHERE ps.rated_games >= $2 AND ps.user_id <> $3 AND u.banned_at IS NULL
		  AND (ps.rating > $4
		    OR (ps.rating = $4 AND ps.rated_games > $5)
		    OR (ps.rating = $4 AND ps.rated_games = $5 AND u.created_at < $6)
		    OR (ps.rating = $4 AND ps.rated_games = $5 AND u.created_at = $6 AND ps.user_id < $1))`,
		userID, minGames, excludeUserID, row.Rating, row.RatedGames, created).Scan(&ahead); err != nil {
		return 0, row, fmt.Errorf("RatingRepository.RatedRank count: %w", err)
	}
	return ahead + 1, row, nil
}
