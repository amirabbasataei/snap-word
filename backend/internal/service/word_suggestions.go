package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

// Sentinel errors of the player-facing suggestion endpoints.
var (
	ErrWordInvalid      = errors.New("invalid word") // characters / length / missing identity / bad reason
	ErrWordInDictionary = errors.New("word already in dictionary")
	ErrWordUnknown      = errors.New("word not in dictionary") // a removal report for a word that is not there
	ErrWordReviewed     = errors.New("word already reviewed")
	ErrWordRateLimited  = errors.New("too many word reports")
)

// Removal report reasons.
const (
	ReasonNotAWord      = "not_a_word"
	ReasonInappropriate = "inappropriate"
)

type wordSuggestionStore interface {
	SubmitReport(ctx context.Context, in repository.WordReportInput) (*repository.WordReportResult, error)
	MyReports(ctx context.Context, userID string, limit int) ([]repository.MyWordReport, error)
}

// WordSuggestionService takes player reports about the dictionary.
type WordSuggestionService struct {
	store wordSuggestionStore
	rdb   *redis.Client
	now   func() time.Time
}

func NewWordSuggestionService(store wordSuggestionStore, rdb *redis.Client) *WordSuggestionService {
	return &WordSuggestionService{store: store, rdb: rdb, now: time.Now}
}

// SubmitWordInput is the body of POST /words/suggestions.
type SubmitWordInput struct {
	Word      string `json:"word"`
	Kind      string `json:"kind"`   // add | remove
	Reason    string `json:"reason"` // remove only: not_a_word | inappropriate
	InstallID string `json:"install_id"`
}

// SubmitWordResult tells the client what happened to the report.
type SubmitWordResult struct {
	Status          string `json:"status"` // pending
	AlreadyReported bool   `json:"already_reported"`
}

// Submit validates and records a report. userID is "" for a guest, who is
// identified by the install id instead.
func (s *WordSuggestionService) Submit(ctx context.Context, userID, ip string, in SubmitWordInput) (*SubmitWordResult, error) {
	word := strings.TrimSpace(in.Word)
	if utf8.RuneCountInString(word) > config.WordSuggestMaxRunes {
		return nil, ErrWordInvalid
	}
	// Same character / length rules as the game; "not in dictionary" is the
	// expected outcome for an addition.
	dictErr := engine.ValidateMove("", word, nil)
	if dictErr != nil && !errors.Is(dictErr, engine.ErrNotInDict) {
		return nil, ErrWordInvalid
	}
	inDict := dictErr == nil

	install := strings.ToLower(in.InstallID)
	key := "u:" + userID
	if userID == "" {
		if !uuidRe.MatchString(install) {
			return nil, ErrWordInvalid
		}
		key = "i:" + install
	}
	if install != "" && !uuidRe.MatchString(install) {
		install = ""
	}

	reason := ""
	switch in.Kind {
	case repository.WordKindAdd:
		if inDict {
			return nil, ErrWordInDictionary
		}
		if engine.IsKnownRejected(word) {
			return nil, ErrWordReviewed
		}
	case repository.WordKindRemove:
		if in.Reason != ReasonNotAWord && in.Reason != ReasonInappropriate {
			return nil, ErrWordInvalid
		}
		reason = in.Reason
		if !inDict {
			return nil, ErrWordUnknown
		}
		if engine.IsAIBlocked(word) {
			return nil, ErrWordReviewed
		}
	default:
		return nil, ErrWordInvalid
	}

	if err := s.allow(ctx, key, ip); err != nil {
		return nil, err
	}

	res, err := s.store.SubmitReport(ctx, repository.WordReportInput{
		Word: word, Kind: in.Kind, ReporterKey: key, UserID: userID, InstallID: install, Reason: reason,
	})
	switch {
	case errors.Is(err, repository.ErrSuggestionNotPending):
		return nil, ErrWordReviewed
	case err != nil:
		return nil, fmt.Errorf("WordSuggestionService.Submit: %w", err)
	}
	return &SubmitWordResult{Status: res.Status, AlreadyReported: !res.Counted}, nil
}

// allow enforces the per-reporter and per-IP daily caps. It fails open when
// Redis is unreachable (the admin queue is the real gate).
func (s *WordSuggestionService) allow(ctx context.Context, key, ip string) error {
	if s.rdb == nil {
		return nil
	}
	day := config.IranDate(s.now()).Format("2006-01-02")
	for _, l := range []struct {
		key   string
		limit int64
	}{
		{"words:rl:r:" + key + ":" + day, config.WordSuggestPerDay},
		{"words:rl:ip:" + ip + ":" + day, config.WordSuggestPerIPPerDay},
	} {
		n, err := s.rdb.Incr(ctx, l.key).Result()
		if err != nil {
			slog.Warn("word suggestions: rate limit check failed", "error", err)
			return nil
		}
		if n == 1 {
			s.rdb.Expire(ctx, l.key, 36*time.Hour)
		}
		if n > l.limit {
			return ErrWordRateLimited
		}
	}
	return nil
}

// MyReportView is one entry of GET /words/suggestions/mine.
type MyReportView struct {
	Word      string    `json:"word"`
	Kind      string    `json:"kind"`
	Status    string    `json:"status"`
	Outcome   string    `json:"outcome,omitempty"`
	Reason    string    `json:"reason,omitempty"`
	Rewarded  bool      `json:"rewarded"`
	CreatedAt time.Time `json:"created_at"`
}

// Mine lists the player's own reports, newest first.
func (s *WordSuggestionService) Mine(ctx context.Context, userID string) ([]MyReportView, error) {
	rows, err := s.store.MyReports(ctx, userID, 100)
	if err != nil {
		return nil, fmt.Errorf("WordSuggestionService.Mine: %w", err)
	}
	out := make([]MyReportView, len(rows))
	for i, r := range rows {
		out[i] = MyReportView{Word: r.Word, Kind: r.Kind, Status: r.Status, Outcome: r.Outcome,
			Reason: r.Reason, Rewarded: r.Rewarded, CreatedAt: r.CreatedAt}
	}
	return out, nil
}
