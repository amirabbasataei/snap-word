package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

var ErrAdminMatchNotFound = errors.New("admin match not found")

// Derived match kinds (the server stores no solo/AI split, see matchKindCTE).
const (
	MatchKindSolo   = "solo"
	MatchKindVersus = "versus"
	MatchKindAI     = "ai"
	MatchKindDaily  = "daily"
)

// AdminMatchListParams filters the matches table. Zero values mean "any".
type AdminMatchListParams struct {
	Query    string // match id, or a player's username / id
	Kind     string
	Status   string // empty = every status except pending
	From, To time.Time
	Page     int
	PageSize int
}

// AdminMatchPlayer is one match_players row with the account's name.
type AdminMatchPlayer struct {
	UserID       string `json:"user_id"`
	Username     string `json:"username"`
	Score        int    `json:"score"`
	IsAI         bool   `json:"is_ai"`
	ContinueUsed bool   `json:"continue_used"`
}

// AdminMatchRow is one match of the list (and the head of the detail).
type AdminMatchRow struct {
	ID          string
	Mode        string
	Status      string
	Kind        string
	WinnerID    string
	At          time.Time
	StartedAt   *time.Time
	EndedAt     *time.Time
	ChainLength int
	Players     []AdminMatchPlayer
	GameState   json.RawMessage // only filled by MatchDetail
}

const adminMatchSelect = `
SELECT m.id, m.mode, m.status,
       CASE
         WHEN m.mode = 'daily' THEN 'daily'
         WHEN p.n >= 2 AND p.has_ai THEN 'ai'
         WHEN p.n >= 2 THEN 'versus'
         ELSE 'solo'
       END AS kind,
       COALESCE(m.winner_id::text, '') AS winner_id,
       COALESCE(m.started_at, m.created_at) AS at, m.started_at, m.ended_at,
       CASE WHEN jsonb_typeof(m.game_state->'word_chain') = 'array'
            THEN jsonb_array_length(m.game_state->'word_chain') ELSE 0 END AS chain_length,
       p.players,
       %s AS game_state
FROM matches m
JOIN LATERAL (
  SELECT count(*) AS n, COALESCE(bool_or(mp.is_ai), false) AS has_ai,
         COALESCE(json_agg(json_build_object(
           'user_id', mp.user_id, 'username', COALESCE(u.username, ''), 'score', mp.score,
           'is_ai', mp.is_ai, 'continue_used', mp.continue_used) ORDER BY mp.is_ai, mp.joined_at, mp.user_id), '[]'::json) AS players
  FROM match_players mp JOIN users u ON u.id = mp.user_id
  WHERE mp.match_id = m.id
) p ON true`

func scanAdminMatch(row interface{ Scan(...any) error }) (*AdminMatchRow, error) {
	var (
		m              AdminMatchRow
		started, ended sql.NullTime
		players        []byte
		state          []byte
	)
	if err := row.Scan(&m.ID, &m.Mode, &m.Status, &m.Kind, &m.WinnerID, &m.At, &started, &ended,
		&m.ChainLength, &players, &state); err != nil {
		return nil, err
	}
	if started.Valid {
		m.StartedAt = &started.Time
	}
	if ended.Valid {
		m.EndedAt = &ended.Time
	}
	if err := json.Unmarshal(players, &m.Players); err != nil {
		return nil, fmt.Errorf("decode players: %w", err)
	}
	m.GameState = state
	return &m, nil
}

// ListMatches returns one page of matches (newest first) and the total count.
func (r *AdminRepository) ListMatches(ctx context.Context, p AdminMatchListParams) ([]AdminMatchRow, int, error) {
	var (
		where []string
		args  []any
	)
	arg := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}

	if p.Status == "" {
		where = append(where, `m.status <> 'pending'`)
	} else {
		where = append(where, `m.status = `+arg(p.Status))
	}
	if p.Query != "" {
		like := arg("%" + escapeLike(p.Query) + "%")
		exact := arg(strings.ToLower(p.Query))
		where = append(where, `(m.id::text = `+exact+` OR EXISTS (
  SELECT 1 FROM match_players qp JOIN users qu ON qu.id = qp.user_id
  WHERE qp.match_id = m.id AND (qu.username ILIKE `+like+` OR qu.id::text = `+exact+`)))`)
	}
	if !p.From.IsZero() {
		where = append(where, `COALESCE(m.started_at, m.created_at) >= `+arg(p.From))
	}
	if !p.To.IsZero() {
		where = append(where, `COALESCE(m.started_at, m.created_at) < `+arg(p.To))
	}
	whereSQL := ` WHERE ` + strings.Join(where, " AND ")
	// The kind is derived from the players, so it is filtered on the joined row.
	kindSQL := ""
	if p.Kind != "" {
		kindSQL = ` AND kind = ` + arg(p.Kind)
	}

	base := fmt.Sprintf(adminMatchSelect, `NULL::jsonb`) + whereSQL
	var total int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM (`+base+`) x WHERE true`+kindSQL, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListMatches count: %w", err)
	}

	limit, offset := arg(p.PageSize), arg((p.Page-1)*p.PageSize)
	q := `SELECT * FROM (` + base + `) x WHERE true` + kindSQL +
		` ORDER BY at DESC, id LIMIT ` + limit + ` OFFSET ` + offset
	rows, err := r.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListMatches: %w", err)
	}
	defer rows.Close()

	out := []AdminMatchRow{}
	for rows.Next() {
		m, err := scanAdminMatch(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("AdminRepository.ListMatches scan: %w", err)
		}
		out = append(out, *m)
	}
	return out, total, rows.Err()
}

// MatchDetail returns one match including its raw game_state.
func (r *AdminRepository) MatchDetail(ctx context.Context, id string) (*AdminMatchRow, error) {
	q := fmt.Sprintf(adminMatchSelect, `m.game_state`) + ` WHERE m.id = $1`
	m, err := scanAdminMatch(r.db.QueryRowContext(ctx, q, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrAdminMatchNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.MatchDetail: %w", err)
	}
	return m, nil
}
