package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// Message kinds stored in player_messages.kind.
const (
	MessageKindPreset = "preset"
	MessageKindCustom = "custom"
)

// PlayerMessageRepository stores what players say to each other in a match.
type PlayerMessageRepository struct {
	db *sql.DB
}

func NewPlayerMessageRepository(db *sql.DB) *PlayerMessageRepository {
	return &PlayerMessageRepository{db: db}
}

// PlayerMessage is one stored message.
type PlayerMessage struct {
	ID        string
	MatchID   string // empty when unknown
	SenderID  string
	Kind      string
	TauntID   string
	Text      string
	CreatedAt time.Time
}

// Insert stores one message. matchID may be empty.
func (r *PlayerMessageRepository) Insert(ctx context.Context, m PlayerMessage) error {
	var match any
	if m.MatchID != "" {
		match = m.MatchID
	}
	if _, err := r.db.ExecContext(ctx,
		`INSERT INTO player_messages (match_id, sender_id, kind, taunt_id, text) VALUES ($1, $2, $3, $4, $5)`,
		match, m.SenderID, m.Kind, m.TauntID, m.Text); err != nil {
		return fmt.Errorf("PlayerMessageRepository.Insert: %w", err)
	}
	return nil
}

// AdminMessageListParams filters the panel's messages table. Zero values mean "any".
type AdminMessageListParams struct {
	Query    string // sender's username / id, or a match id; also matches the text
	Kind     string
	From, To time.Time
	Page     int
	PageSize int
}

// AdminMessageRow is one message with the sender's and the opponent's names.
type AdminMessageRow struct {
	PlayerMessage
	SenderName   string
	SenderBanned bool
	// Opponent is the other human or AI in the match; empty when the match is unknown.
	OpponentID   string
	OpponentName string
}

// ListMessages returns one page of messages (newest first) and the total.
func (r *AdminRepository) ListMessages(ctx context.Context, p AdminMessageListParams) ([]AdminMessageRow, int, error) {
	var (
		where []string
		args  []any
	)
	arg := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	if p.Kind != "" {
		where = append(where, `pm.kind = `+arg(p.Kind))
	}
	if p.Query != "" {
		like := arg("%" + escapeLike(p.Query) + "%")
		exact := arg(strings.ToLower(p.Query))
		where = append(where, `(u.username ILIKE `+like+` OR pm.text ILIKE `+like+
			` OR pm.sender_id::text = `+exact+` OR pm.match_id::text = `+exact+`)`)
	}
	if !p.From.IsZero() {
		where = append(where, `pm.created_at >= `+arg(p.From))
	}
	if !p.To.IsZero() {
		where = append(where, `pm.created_at < `+arg(p.To))
	}
	cond := ""
	if len(where) > 0 {
		cond = " WHERE " + strings.Join(where, " AND ")
	}
	const from = ` FROM player_messages pm JOIN users u ON u.id = pm.sender_id`

	var total int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*)`+from+cond, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListMessages count: %w", err)
	}

	limit, offset := arg(p.PageSize), arg((p.Page-1)*p.PageSize)
	rows, err := r.db.QueryContext(ctx,
		`SELECT pm.id, COALESCE(pm.match_id::text, ''), pm.sender_id, pm.kind, pm.taunt_id, pm.text, pm.created_at,
		        u.username, u.banned_at IS NOT NULL,
		        COALESCE(opp.user_id::text, ''), COALESCE(ou.username, '')`+from+`
		 LEFT JOIN LATERAL (
		   SELECT mp.user_id FROM match_players mp
		   WHERE mp.match_id = pm.match_id AND mp.user_id <> pm.sender_id
		   ORDER BY mp.joined_at LIMIT 1
		 ) opp ON pm.match_id IS NOT NULL
		 LEFT JOIN users ou ON ou.id = opp.user_id`+cond+
			` ORDER BY pm.created_at DESC, pm.id LIMIT `+limit+` OFFSET `+offset, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListMessages: %w", err)
	}
	defer rows.Close()
	out := []AdminMessageRow{}
	for rows.Next() {
		var m AdminMessageRow
		if err := rows.Scan(&m.ID, &m.MatchID, &m.SenderID, &m.Kind, &m.TauntID, &m.Text, &m.CreatedAt,
			&m.SenderName, &m.SenderBanned, &m.OpponentID, &m.OpponentName); err != nil {
			return nil, 0, fmt.Errorf("AdminRepository.ListMessages scan: %w", err)
		}
		out = append(out, m)
	}
	return out, total, rows.Err()
}
