package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

var ErrMatchNotFound = errors.New("match not found")

type Match struct {
	ID        string
	Mode      string
	Status    string
	WinnerID  *string
	GameState json.RawMessage
	StartedAt *time.Time
	EndedAt   *time.Time
	CreatedAt time.Time
}

type MatchPlayer struct {
	MatchID      string
	UserID       string
	Score        int
	IsAI         bool
	ContinueUsed bool
	JoinedAt     time.Time
}

type MatchRepository struct {
	db *sql.DB
}

func NewMatchRepository(db *sql.DB) *MatchRepository {
	return &MatchRepository{db: db}
}

func (r *MatchRepository) CreateMatch(
	ctx context.Context,
	mode, status string,
	winnerID *string,
	gameState json.RawMessage,
	startedAt, endedAt *time.Time,
) (*Match, error) {
	const q = `
		INSERT INTO matches (mode, status, winner_id, game_state, started_at, ended_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, mode, status, winner_id, game_state, started_at, ended_at, created_at`

	return r.scanMatch(r.db.QueryRowContext(ctx, q,
		mode, status, winnerID, []byte(gameState), startedAt, endedAt))
}

func (r *MatchRepository) AddMatchPlayer(ctx context.Context, matchID, userID string, score int) error {
	const q = `
		INSERT INTO match_players (match_id, user_id, score)
		VALUES ($1, $2, $3)`
	_, err := r.db.ExecContext(ctx, q, matchID, userID, score)
	if err != nil {
		return fmt.Errorf("AddMatchPlayer: %w", err)
	}
	return nil
}

func (r *MatchRepository) GetMatch(ctx context.Context, matchID string) (*Match, error) {
	const q = `
		SELECT id, mode, status, winner_id, game_state, started_at, ended_at, created_at
		FROM matches WHERE id = $1`
	m, err := r.scanMatch(r.db.QueryRowContext(ctx, q, matchID))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrMatchNotFound
	}
	return m, err
}

func (r *MatchRepository) GetMatchPlayers(ctx context.Context, matchID string) ([]*MatchPlayer, error) {
	const q = `
		SELECT match_id, user_id, score, is_ai, continue_used, joined_at
		FROM match_players WHERE match_id = $1`

	rows, err := r.db.QueryContext(ctx, q, matchID)
	if err != nil {
		return nil, fmt.Errorf("GetMatchPlayers: %w", err)
	}
	defer rows.Close()

	var players []*MatchPlayer
	for rows.Next() {
		p := &MatchPlayer{}
		if err := rows.Scan(&p.MatchID, &p.UserID, &p.Score, &p.IsAI, &p.ContinueUsed, &p.JoinedAt); err != nil {
			return nil, fmt.Errorf("GetMatchPlayers scan: %w", err)
		}
		players = append(players, p)
	}
	return players, rows.Err()
}

func (r *MatchRepository) UpdateMatchStatus(ctx context.Context, matchID, status string) error {
	const q = `UPDATE matches SET status = $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, q, status, matchID)
	if err != nil {
		return fmt.Errorf("UpdateMatchStatus: %w", err)
	}
	return nil
}

func (r *MatchRepository) SaveGameState(ctx context.Context, matchID string, state json.RawMessage) error {
	const q = `UPDATE matches SET game_state = $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, q, []byte(state), matchID)
	if err != nil {
		return fmt.Errorf("SaveGameState: %w", err)
	}
	return nil
}

func (r *MatchRepository) SetContinueUsed(ctx context.Context, matchID, userID string) error {
	const q = `UPDATE match_players SET continue_used = true WHERE match_id = $1 AND user_id = $2`
	_, err := r.db.ExecContext(ctx, q, matchID, userID)
	if err != nil {
		return fmt.Errorf("SetContinueUsed: %w", err)
	}
	return nil
}

// FindSoloMatch returns a match where the given user is a player, mode matches, and started_at matches.
// Used for idempotent solo game sync uploads.
func (r *MatchRepository) FindSoloMatch(ctx context.Context, userID string, mode string, startedAt time.Time) (*Match, error) {
	const q = `
		SELECT m.id, m.mode, m.status, m.winner_id, m.game_state, m.started_at, m.ended_at, m.created_at
		FROM matches m
		JOIN match_players mp ON mp.match_id = m.id
		WHERE mp.user_id = $1 AND m.mode = $2 AND m.started_at = $3
		LIMIT 1`

	m, err := r.scanMatch(r.db.QueryRowContext(ctx, q, userID, mode, startedAt))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrMatchNotFound
	}
	return m, err
}

func (r *MatchRepository) scanMatch(row *sql.Row) (*Match, error) {
	m := &Match{}
	var winnerID sql.NullString
	var gs []byte
	var startedAt, endedAt sql.NullTime

	err := row.Scan(&m.ID, &m.Mode, &m.Status, &winnerID, &gs, &startedAt, &endedAt, &m.CreatedAt)
	if err != nil {
		return nil, err
	}

	if winnerID.Valid {
		m.WinnerID = &winnerID.String
	}
	m.GameState = gs
	if startedAt.Valid {
		m.StartedAt = &startedAt.Time
	}
	if endedAt.Valid {
		m.EndedAt = &endedAt.Time
	}
	return m, nil
}
