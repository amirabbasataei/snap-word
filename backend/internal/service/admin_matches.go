package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

var (
	ErrAdminMatchNotFound = errors.New("match not found")
	ErrInvalidMatchFilter = errors.New("invalid match filter")
)

const (
	AdminMatchesDefaultPageSize = 25
	AdminMatchesMaxPageSize     = 100
)

type adminMatchStore interface {
	ListMatches(ctx context.Context, p repository.AdminMatchListParams) ([]repository.AdminMatchRow, int, error)
	MatchDetail(ctx context.Context, id string) (*repository.AdminMatchRow, error)
}

// AdminMatchService backs the panel's read-only matches pages.
type AdminMatchService struct {
	store adminMatchStore
}

func NewAdminMatchService(store adminMatchStore) *AdminMatchService {
	return &AdminMatchService{store: store}
}

// MatchListQuery is the unvalidated query of GET /admin/matches.
type MatchListQuery struct {
	Q        string
	Kind     string // solo | versus | ai | daily
	Status   string // active | finished | abandoned | pending
	From, To string // YYYY-MM-DD, Iran days, inclusive
	Page     int
	PageSize int
}

// AdminMatchItem is one row of the matches table.
type AdminMatchItem struct {
	ID          string                        `json:"id"`
	Mode        string                        `json:"mode"`
	Status      string                        `json:"status"`
	Kind        string                        `json:"kind"`
	At          time.Time                     `json:"at"`
	StartedAt   *time.Time                    `json:"started_at"`
	EndedAt     *time.Time                    `json:"ended_at"`
	DurationSec *int                          `json:"duration_sec"`
	ChainLength int                           `json:"chain_length"`
	WinnerID    string                        `json:"winner_id"`
	Players     []repository.AdminMatchPlayer `json:"players"`
}

// AdminMatchPage is a page of the matches table.
type AdminMatchPage struct {
	Items    []AdminMatchItem `json:"items"`
	Total    int              `json:"total"`
	Page     int              `json:"page"`
	PageSize int              `json:"page_size"`
}

// AdminMatchDetail adds the word chain to a list row.
type AdminMatchDetail struct {
	AdminMatchItem
	WordChain []string `json:"word_chain"`
}

func matchItem(r repository.AdminMatchRow) AdminMatchItem {
	it := AdminMatchItem{
		ID: r.ID, Mode: r.Mode, Status: r.Status, Kind: r.Kind, At: r.At, StartedAt: r.StartedAt,
		EndedAt: r.EndedAt, ChainLength: r.ChainLength, WinnerID: r.WinnerID, Players: r.Players,
	}
	if it.Players == nil {
		it.Players = []repository.AdminMatchPlayer{}
	}
	if r.StartedAt != nil && r.EndedAt != nil && r.EndedAt.After(*r.StartedAt) {
		d := int(r.EndedAt.Sub(*r.StartedAt).Seconds())
		it.DurationSec = &d
	}
	return it
}

// iranDayStart parses YYYY-MM-DD as midnight Iran time.
func iranDayStart(s string) (time.Time, error) {
	t, err := time.ParseInLocation("2006-01-02", s, config.IranLocation)
	if err != nil {
		return time.Time{}, fmt.Errorf("%w: date %q", ErrInvalidMatchFilter, s)
	}
	return t, nil
}

func (s *AdminMatchService) List(ctx context.Context, q MatchListQuery) (*AdminMatchPage, error) {
	switch q.Kind {
	case "", repository.MatchKindSolo, repository.MatchKindVersus, repository.MatchKindAI, repository.MatchKindDaily:
	default:
		return nil, ErrInvalidMatchFilter
	}
	switch q.Status {
	case "", "pending", "active", "finished", "abandoned":
	default:
		return nil, ErrInvalidMatchFilter
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.PageSize < 1 {
		q.PageSize = AdminMatchesDefaultPageSize
	}
	if q.PageSize > AdminMatchesMaxPageSize {
		q.PageSize = AdminMatchesMaxPageSize
	}

	p := repository.AdminMatchListParams{
		Query: strings.TrimSpace(q.Q), Kind: q.Kind, Status: q.Status, Page: q.Page, PageSize: q.PageSize,
	}
	if q.From != "" {
		from, err := iranDayStart(q.From)
		if err != nil {
			return nil, err
		}
		p.From = from
	}
	if q.To != "" {
		to, err := iranDayStart(q.To)
		if err != nil {
			return nil, err
		}
		p.To = to.AddDate(0, 0, 1) // inclusive day
	}
	if !p.From.IsZero() && !p.To.IsZero() && !p.To.After(p.From) {
		return nil, fmt.Errorf("%w: from is after to", ErrInvalidMatchFilter)
	}

	rows, total, err := s.store.ListMatches(ctx, p)
	if err != nil {
		return nil, fmt.Errorf("AdminMatchService.List: %w", err)
	}
	out := &AdminMatchPage{Items: make([]AdminMatchItem, len(rows)), Total: total, Page: q.Page, PageSize: q.PageSize}
	for i, r := range rows {
		out.Items[i] = matchItem(r)
	}
	return out, nil
}

func (s *AdminMatchService) Detail(ctx context.Context, id string) (*AdminMatchDetail, error) {
	if !uuidRe.MatchString(id) {
		return nil, ErrAdminMatchNotFound
	}
	row, err := s.store.MatchDetail(ctx, strings.ToLower(id))
	if errors.Is(err, repository.ErrAdminMatchNotFound) {
		return nil, ErrAdminMatchNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminMatchService.Detail: %w", err)
	}
	d := &AdminMatchDetail{AdminMatchItem: matchItem(*row), WordChain: []string{}}
	if len(row.GameState) > 0 {
		var gs struct {
			WordChain []string `json:"word_chain"`
		}
		if json.Unmarshal(row.GameState, &gs) == nil && gs.WordChain != nil {
			d.WordChain = gs.WordChain
		}
	}
	return d, nil
}
