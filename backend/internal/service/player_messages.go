package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"wordchain/backend/internal/repository"
)

var (
	// ErrInvalidMessageFilter: an unknown kind or a bad date range.
	ErrInvalidMessageFilter = errors.New("invalid message filter")
)

type messageStore interface {
	Insert(ctx context.Context, m repository.PlayerMessage) error
}

// MessageService stores the messages players send in matches.
type MessageService struct {
	store messageStore
}

func NewMessageService(store messageStore) *MessageService { return &MessageService{store: store} }

// RecordPlayerMessage stores one delivered message. kind is preset or custom.
func (s *MessageService) RecordPlayerMessage(ctx context.Context, matchID, senderID, kind, tauntID, text string) error {
	if err := s.store.Insert(ctx, repository.PlayerMessage{
		MatchID: matchID, SenderID: senderID, Kind: kind, TauntID: tauntID, Text: text,
	}); err != nil {
		return fmt.Errorf("MessageService.RecordPlayerMessage: %w", err)
	}
	return nil
}

const (
	AdminMessagesDefaultPageSize = 25
	AdminMessagesMaxPageSize     = 100
)

type adminMessageStore interface {
	ListMessages(ctx context.Context, p repository.AdminMessageListParams) ([]repository.AdminMessageRow, int, error)
}

// AdminMessageService backs the panel's read-only messages page.
type AdminMessageService struct {
	store adminMessageStore
}

func NewAdminMessageService(store adminMessageStore) *AdminMessageService {
	return &AdminMessageService{store: store}
}

// MessageListQuery is the unvalidated query of GET /admin/messages.
type MessageListQuery struct {
	Q        string
	Kind     string // preset | custom
	From, To string // YYYY-MM-DD, Iran days, inclusive
	Page     int
	PageSize int
}

// AdminMessageItem is one row of the messages table.
type AdminMessageItem struct {
	ID           string    `json:"id"`
	At           time.Time `json:"at"`
	Kind         string    `json:"kind"`
	TauntID      string    `json:"taunt_id"`
	Text         string    `json:"text"`
	MatchID      string    `json:"match_id"`
	SenderID     string    `json:"sender_id"`
	SenderName   string    `json:"sender_name"`
	SenderBanned bool      `json:"sender_banned"`
	OpponentID   string    `json:"opponent_id"`
	OpponentName string    `json:"opponent_name"`
}

// AdminMessagePage is a page of the messages table.
type AdminMessagePage struct {
	Items    []AdminMessageItem `json:"items"`
	Total    int                `json:"total"`
	Page     int                `json:"page"`
	PageSize int                `json:"page_size"`
}

func (s *AdminMessageService) List(ctx context.Context, q MessageListQuery) (*AdminMessagePage, error) {
	switch q.Kind {
	case "", repository.MessageKindPreset, repository.MessageKindCustom:
	default:
		return nil, ErrInvalidMessageFilter
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.PageSize < 1 {
		q.PageSize = AdminMessagesDefaultPageSize
	}
	if q.PageSize > AdminMessagesMaxPageSize {
		q.PageSize = AdminMessagesMaxPageSize
	}
	p := repository.AdminMessageListParams{
		Query: strings.TrimSpace(q.Q), Kind: q.Kind, Page: q.Page, PageSize: q.PageSize,
	}
	if q.From != "" {
		from, err := iranDayStart(q.From)
		if err != nil {
			return nil, ErrInvalidMessageFilter
		}
		p.From = from
	}
	if q.To != "" {
		to, err := iranDayStart(q.To)
		if err != nil {
			return nil, ErrInvalidMessageFilter
		}
		p.To = to.AddDate(0, 0, 1)
	}
	if !p.From.IsZero() && !p.To.IsZero() && !p.To.After(p.From) {
		return nil, ErrInvalidMessageFilter
	}

	rows, total, err := s.store.ListMessages(ctx, p)
	if err != nil {
		return nil, fmt.Errorf("AdminMessageService.List: %w", err)
	}
	items := make([]AdminMessageItem, 0, len(rows))
	for _, r := range rows {
		items = append(items, AdminMessageItem{
			ID: r.ID, At: r.CreatedAt, Kind: r.Kind, TauntID: r.TauntID, Text: r.Text, MatchID: r.MatchID,
			SenderID: r.SenderID, SenderName: r.SenderName, SenderBanned: r.SenderBanned,
			OpponentID: r.OpponentID, OpponentName: r.OpponentName,
		})
	}
	return &AdminMessagePage{Items: items, Total: total, Page: q.Page, PageSize: q.PageSize}, nil
}
