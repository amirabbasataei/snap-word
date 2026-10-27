package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

// Sentinel errors of the admin word endpoints (the repository's
// ErrSuggestion* errors pass through wrapped).
var (
	ErrWordBadAction = errors.New("invalid word action")
	ErrWordBadQuery  = errors.New("invalid word query")
	ErrBulkTooMany   = errors.New("too many suggestions in one bulk action")
)

// Review actions of POST /admin/words/suggestions/bulk and direct changes.
const (
	WordActionApprove = "approve"
	WordActionReject  = "reject"
)

type adminWordStore interface {
	ListSuggestions(ctx context.Context, p repository.WordListParams) ([]repository.AdminWordSuggestion, int, error)
	SuggestionCounts(ctx context.Context) (map[string]int, error)
	GetSuggestion(ctx context.Context, id int64) (*repository.AdminWordSuggestion, []repository.AdminWordReport, error)
	ApproveSuggestion(ctx context.Context, id int64, admin, note, outcome string, rewardCoins int) (*repository.ApprovedWord, error)
	RejectSuggestion(ctx context.Context, id int64, admin, note string) (string, error)
	SetOverride(ctx context.Context, word string, a repository.OverrideAction) (repository.DictOverride, error)
	SuggestionsForWord(ctx context.Context, word string) ([]repository.AdminWordSuggestion, error)
}

type wordPusher interface {
	SendToUser(ctx context.Context, userID, title, body string) error
}

// AdminWordService is the review queue and manual dictionary editor of the panel.
type AdminWordService struct {
	store  adminWordStore
	dict   *DictionaryService
	misses *WordMissService
	push   wordPusher
	audit  *AuditService
}

func NewAdminWordService(store adminWordStore, dict *DictionaryService, misses *WordMissService, push wordPusher, audit *AuditService) *AdminWordService {
	return &AdminWordService{store: store, dict: dict, misses: misses, push: push, audit: audit}
}

func wordTarget(word string) AuditTarget { return AuditTarget{Type: "word", ID: word} }

// actorName is what the review rows record as reviewer.
func actorName(a AuditActor) string {
	if a.Name == "" {
		return "script"
	}
	return a.Name
}

// optionalNote validates a free-text note that may be left empty.
func optionalNote(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return "", nil
	}
	return cleanReason(raw)
}

// ---- review queue ----

// WordSuggestionItem is one row of the review queue.
type WordSuggestionItem struct {
	ID             int64      `json:"id"`
	Word           string     `json:"word"`
	Kind           string     `json:"kind"`
	Status         string     `json:"status"`
	Outcome        string     `json:"outcome"`
	Reporters      int        `json:"reporters"`
	NotAWord       int        `json:"not_a_word"`
	Inappropriate  int        `json:"inappropriate"`
	ReviewNote     string     `json:"review_note"`
	ReviewedBy     string     `json:"reviewed_by"`
	ReviewedAt     *time.Time `json:"reviewed_at"`
	CreatedAt      time.Time  `json:"created_at"`
	LastReportedAt time.Time  `json:"last_reported_at"`
	InDictionary   bool       `json:"in_dictionary"`
	AIBlocked      bool       `json:"ai_blocked"`
	KnownRejected  bool       `json:"known_rejected"`
	Warnings       []string   `json:"warnings"`
}

func suggestionItem(r repository.AdminWordSuggestion) WordSuggestionItem {
	return WordSuggestionItem{
		ID: r.ID, Word: r.Word, Kind: r.Kind, Status: r.Status, Outcome: r.Outcome, Reporters: r.Reporters,
		NotAWord: r.NotAWord, Inappropriate: r.Inappropriate, ReviewNote: r.ReviewNote, ReviewedBy: r.ReviewedBy,
		ReviewedAt: r.ReviewedAt, CreatedAt: r.CreatedAt, LastReportedAt: r.LastReportedAt,
		InDictionary: engine.IsValid(r.Word), AIBlocked: engine.IsAIBlocked(r.Word),
		KnownRejected: engine.IsKnownRejected(r.Word), Warnings: WordWarnings(r.Word),
	}
}

// WordQueueQuery is the filter of GET /admin/words/suggestions.
type WordQueueQuery struct {
	Status   string // pending (default) | approved | rejected | all
	Kind     string // add | remove | "" (all)
	Query    string
	Sort     string // reporters (default) | recent
	Page     int
	PageSize int
}

// WordQueuePage is one page of the queue with the pending counts for the tabs.
type WordQueuePage struct {
	Items    []WordSuggestionItem `json:"items"`
	Total    int                  `json:"total"`
	Page     int                  `json:"page"`
	PageSize int                  `json:"page_size"`
	Pending  map[string]int       `json:"pending"`
}

// Queue lists suggestions.
func (s *AdminWordService) Queue(ctx context.Context, q WordQueueQuery) (*WordQueuePage, error) {
	if q.Status == "" {
		q.Status = repository.WordPending
	}
	switch q.Status {
	case repository.WordPending, repository.WordApproved, repository.WordRejected:
	case "all":
		q.Status = ""
	default:
		return nil, ErrWordBadQuery
	}
	if q.Kind != "" && q.Kind != repository.WordKindAdd && q.Kind != repository.WordKindRemove {
		return nil, ErrWordBadQuery
	}
	if q.Sort != "" && q.Sort != "reporters" && q.Sort != "recent" {
		return nil, ErrWordBadQuery
	}
	if q.PageSize == 0 {
		q.PageSize = config.WordAdminPageSizeDefault
	}
	if q.Page == 0 {
		q.Page = 1
	}
	if q.Page < 1 || q.PageSize < 1 || q.PageSize > config.WordAdminPageSizeMax || utf8.RuneCountInString(q.Query) > 40 {
		return nil, ErrWordBadQuery
	}

	rows, total, err := s.store.ListSuggestions(ctx, repository.WordListParams{
		Status: q.Status, Kind: q.Kind, Query: strings.TrimSpace(q.Query), Recent: q.Sort == "recent",
		Limit: q.PageSize, Offset: (q.Page - 1) * q.PageSize,
	})
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Queue: %w", err)
	}
	counts, err := s.store.SuggestionCounts(ctx)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Queue: %w", err)
	}
	out := &WordQueuePage{Items: make([]WordSuggestionItem, len(rows)), Total: total, Page: q.Page, PageSize: q.PageSize, Pending: counts}
	for i, r := range rows {
		out.Items[i] = suggestionItem(r)
	}
	return out, nil
}

// WordReportItem is one reporter of a suggestion ("" username = guest).
type WordReportItem struct {
	Username  string    `json:"username"`
	Guest     bool      `json:"guest"`
	Reason    string    `json:"reason"`
	CreatedAt time.Time `json:"created_at"`
}

// WordSuggestionDetail is a suggestion with its reporters.
type WordSuggestionDetail struct {
	WordSuggestionItem
	Reports []WordReportItem `json:"reports"`
}

// Detail returns one suggestion with who reported it.
func (s *AdminWordService) Detail(ctx context.Context, id int64) (*WordSuggestionDetail, error) {
	sug, reports, err := s.store.GetSuggestion(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Detail: %w", err)
	}
	out := &WordSuggestionDetail{WordSuggestionItem: suggestionItem(*sug), Reports: make([]WordReportItem, len(reports))}
	for i, r := range reports {
		out.Reports[i] = WordReportItem{Username: r.Username, Guest: r.UserID == "", Reason: r.Reason, CreatedAt: r.CreatedAt}
	}
	return out, nil
}

// ---- decisions ----

// ApproveResult reports what an approval did.
type ApproveResult struct {
	Word     string `json:"word"`
	Outcome  string `json:"outcome"`
	Seq      int64  `json:"seq"`
	Rewarded bool   `json:"rewarded"`
}

// Approve accepts a pending suggestion. For a removal suggestion outcome must
// be "remove" or "ai_block"; a removal needs a reason (a panel session cannot
// delete a word silently), other approvals take an optional note.
func (s *AdminWordService) Approve(ctx context.Context, actor AuditActor, id int64, outcome, note string) (*ApproveResult, error) {
	var err error
	if outcome == repository.WordOutcomeRemove {
		note, err = ReasonFor(actor, note)
	} else {
		note, err = optionalNote(note)
	}
	if err != nil {
		return nil, err
	}

	res, err := s.store.ApproveSuggestion(ctx, id, actorName(actor), note, outcome, config.CoinWordSuggestion)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Approve: %w", err)
	}
	s.dict.Apply(res.Override)
	if res.Kind == repository.WordKindAdd {
		s.dropMiss(ctx, res.Word)
	}
	s.audit.LogRecord(ctx, actor, "word.approve", wordTarget(res.Word), map[string]any{
		"suggestion_id": id, "kind": res.Kind, "outcome": res.Outcome, "note": note,
		"reward_user_id": res.RewardUserID, "reward_created": res.RewardCreated, "seq": res.Override.Seq,
	})
	if res.RewardCreated {
		s.notifyApproved(res.RewardUserID, res.Word)
	}
	return &ApproveResult{Word: res.Word, Outcome: res.Outcome, Seq: res.Override.Seq, Rewarded: res.RewardCreated}, nil
}

// Reject turns a pending suggestion down.
func (s *AdminWordService) Reject(ctx context.Context, actor AuditActor, id int64, note string) (string, error) {
	note, err := optionalNote(note)
	if err != nil {
		return "", err
	}
	word, err := s.store.RejectSuggestion(ctx, id, actorName(actor), note)
	if err != nil {
		return "", fmt.Errorf("AdminWordService.Reject: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "word.reject", wordTarget(word), map[string]any{"suggestion_id": id, "note": note})
	return word, nil
}

// BulkFailure names a suggestion a bulk action could not process.
type BulkFailure struct {
	ID    int64  `json:"id"`
	Error string `json:"error"`
}

// BulkResult counts a bulk action.
type BulkResult struct {
	Done   int           `json:"done"`
	Failed []BulkFailure `json:"failed"`
}

// Bulk approves or rejects many suggestions one by one; a failure does not
// stop the rest. Removal suggestions cannot be approved in bulk (they need an
// outcome and a reason each).
func (s *AdminWordService) Bulk(ctx context.Context, actor AuditActor, ids []int64, action, note string) (*BulkResult, error) {
	if len(ids) == 0 || len(ids) > config.WordAdminBulkMax {
		return nil, ErrBulkTooMany
	}
	if action != WordActionApprove && action != WordActionReject {
		return nil, ErrWordBadAction
	}
	out := &BulkResult{Failed: []BulkFailure{}}
	for _, id := range ids {
		var err error
		if action == WordActionApprove {
			_, err = s.Approve(ctx, actor, id, "", note)
		} else {
			_, err = s.Reject(ctx, actor, id, note)
		}
		if err != nil {
			code := bulkErrorCode(err)
			if code == "internal_error" {
				slog.Error("bulk word action failed", "id", id, "action", action, "error", err)
			}
			out.Failed = append(out.Failed, BulkFailure{ID: id, Error: code})
			continue
		}
		out.Done++
	}
	return out, nil
}

func bulkErrorCode(err error) string {
	switch {
	case errors.Is(err, repository.ErrSuggestionNotFound):
		return "not_found"
	case errors.Is(err, repository.ErrSuggestionNotPending):
		return "already_reviewed"
	case errors.Is(err, repository.ErrSuggestionOutcome):
		return "outcome_required"
	case errors.Is(err, ErrReasonRequired):
		return "reason_required"
	default:
		return "internal_error"
	}
}

// ---- manual editor ----

// SetWord changes the dictionary directly, outside any suggestion: add a word
// players keep typing, remove a bad one, or (un)block it for the AI. A reason
// is required for panel sessions.
func (s *AdminWordService) SetWord(ctx context.Context, actor AuditActor, word string, action repository.OverrideAction, reason string) (*DictChange, error) {
	reason, err := ReasonFor(actor, reason)
	if err != nil {
		return nil, err
	}
	word = strings.TrimSpace(word)
	if utf8.RuneCountInString(word) > config.WordSuggestMaxRunes {
		return nil, ErrWordInvalid
	}
	if verr := engine.ValidateMove("", word, nil); verr != nil && !errors.Is(verr, engine.ErrNotInDict) {
		return nil, ErrWordInvalid
	}
	switch action {
	case repository.OverrideAdd, repository.OverrideRemove, repository.OverrideAIBlock, repository.OverrideAIUnblock:
	default:
		return nil, ErrWordBadAction
	}

	ov, err := s.store.SetOverride(ctx, word, action)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.SetWord: %w", err)
	}
	s.dict.Apply(ov)
	if action == repository.OverrideAdd || action == repository.OverrideRemove {
		s.dropMiss(ctx, word)
	}
	s.audit.LogRecord(ctx, actor, "word.set", wordTarget(word), map[string]any{"action": string(action), "reason": reason, "seq": ov.Seq})
	return &DictChange{Word: ov.Word, Present: ov.Present, AIBlocked: ov.AIBlocked}, nil
}

// ---- lookup, misses, export ----

// WordLookup describes one word for the lookup box.
type WordLookup struct {
	Word          string               `json:"word"`
	InDictionary  bool                 `json:"in_dictionary"`
	InBase        bool                 `json:"in_base"`
	AIBlocked     bool                 `json:"ai_blocked"`
	KnownRejected bool                 `json:"known_rejected"`
	Warnings      []string             `json:"warnings"`
	Suggestions   []WordSuggestionItem `json:"suggestions"`
}

// Lookup reports the dictionary state of a word and every suggestion about it.
func (s *AdminWordService) Lookup(ctx context.Context, word string) (*WordLookup, error) {
	word = strings.TrimSpace(word)
	if word == "" || utf8.RuneCountInString(word) > config.WordSuggestMaxRunes {
		return nil, ErrWordBadQuery
	}
	rows, err := s.store.SuggestionsForWord(ctx, word)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Lookup: %w", err)
	}
	out := &WordLookup{
		Word: word, InDictionary: engine.IsValid(word), InBase: engine.InBase(word), AIBlocked: engine.IsAIBlocked(word),
		KnownRejected: engine.IsKnownRejected(word), Warnings: WordWarnings(word), Suggestions: make([]WordSuggestionItem, len(rows)),
	}
	for i, r := range rows {
		out.Suggestions[i] = suggestionItem(r)
	}
	return out, nil
}

// MissItem is one most-rejected word of multiplayer play.
type MissItem struct {
	Word          string   `json:"word"`
	Count         int      `json:"count"`
	InDictionary  bool     `json:"in_dictionary"`
	KnownRejected bool     `json:"known_rejected"`
	Warnings      []string `json:"warnings"`
}

// Misses returns the most-rejected words, already-fixed ones flagged.
func (s *AdminWordService) Misses(ctx context.Context, n int) ([]MissItem, error) {
	if n <= 0 || n > 200 {
		n = 100
	}
	top, err := s.misses.Top(ctx, n)
	if err != nil {
		return nil, fmt.Errorf("AdminWordService.Misses: %w", err)
	}
	out := make([]MissItem, len(top))
	for i, m := range top {
		out[i] = MissItem{Word: m.Word, Count: m.Count, InDictionary: engine.IsValid(m.Word),
			KnownRejected: engine.IsKnownRejected(m.Word), Warnings: WordWarnings(m.Word)}
	}
	return out, nil
}

// DismissMiss removes a word from the tally.
func (s *AdminWordService) DismissMiss(ctx context.Context, actor AuditActor, word string) error {
	if err := s.misses.Dismiss(ctx, strings.TrimSpace(word)); err != nil {
		return fmt.Errorf("AdminWordService.DismissMiss: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "word.dismiss_miss", wordTarget(word), nil)
	return nil
}

// WordExport lists the overlay in the form needed to fold it into fa.txt.
type WordExport struct {
	Seq       int64    `json:"seq"`
	Added     []string `json:"added"`      // present now, absent from fa.txt
	Removed   []string `json:"removed"`    // in fa.txt, removed since
	AIBlocked []string `json:"ai_blocked"` // kept in fa.txt, never played by the AI (stay in the overlay)
}

// Export returns the words to append to / delete from fa.txt at the next release.
func (s *AdminWordService) Export() *WordExport {
	out := &WordExport{Added: []string{}, Removed: []string{}, AIBlocked: []string{}}
	for _, o := range s.dict.Overrides() {
		if o.Seq > out.Seq {
			out.Seq = o.Seq
		}
		switch {
		case o.Present && !engine.InBase(o.Word):
			out.Added = append(out.Added, o.Word)
		case !o.Present && engine.InBase(o.Word):
			out.Removed = append(out.Removed, o.Word)
		}
		if o.AIBlocked {
			out.AIBlocked = append(out.AIBlocked, o.Word)
		}
	}
	return out
}

func (s *AdminWordService) dropMiss(ctx context.Context, word string) {
	if err := s.misses.Dismiss(ctx, word); err != nil {
		slog.Warn("could not clear word from miss tally", "word", word, "error", err)
	}
}

// notifyApproved sends the reporter the Persian "your word was added" push. It
// runs off the request path; FCM being unconfigured makes it a logged no-op.
func (s *AdminWordService) notifyApproved(userID, word string) {
	if s.push == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		body := fmt.Sprintf("کلمهٔ «%s» به دیکشنری اضافه شد. %s سکه جایزه در بخش جوایز منتظر توست.", word, faNum(config.CoinWordSuggestion))
		if err := s.push.SendToUser(ctx, userID, "کلمه‌ات تأیید شد", body); err != nil {
			slog.Warn("word approval push failed", "error", err)
		}
	}()
}
