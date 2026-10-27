package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Sentinel errors of the word-suggestion store.
var (
	ErrSuggestionNotFound   = errors.New("word suggestion not found")
	ErrSuggestionNotPending = errors.New("word suggestion already reviewed")
	ErrSuggestionOutcome    = errors.New("invalid approval outcome")
)

// Suggestion kinds, statuses and approval outcomes.
const (
	WordKindAdd    = "add"
	WordKindRemove = "remove"

	WordPending  = "pending"
	WordApproved = "approved"
	WordRejected = "rejected"

	WordOutcomeAdd     = "add"
	WordOutcomeRemove  = "remove"
	WordOutcomeAIBlock = "ai_block"
)

// WordRepository stores player word suggestions and the dictionary overlay.
type WordRepository struct {
	db *sql.DB
}

func NewWordRepository(db *sql.DB) *WordRepository { return &WordRepository{db: db} }

// DictOverride is one word's desired state relative to fa.txt.
type DictOverride struct {
	Word      string
	Present   bool
	AIBlocked bool
	Seq       int64
	UpdatedAt time.Time
}

// LoadOverrides returns every override ordered by seq.
func (r *WordRepository) LoadOverrides(ctx context.Context) ([]DictOverride, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT word, present, ai_blocked, seq, updated_at FROM dictionary_overrides ORDER BY seq`)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.LoadOverrides: %w", err)
	}
	defer rows.Close()
	out := []DictOverride{}
	for rows.Next() {
		var o DictOverride
		if err := rows.Scan(&o.Word, &o.Present, &o.AIBlocked, &o.Seq, &o.UpdatedAt); err != nil {
			return nil, fmt.Errorf("WordRepository.LoadOverrides scan: %w", err)
		}
		out = append(out, o)
	}
	return out, rows.Err()
}

// OverrideAction is a direct dictionary change.
type OverrideAction string

const (
	OverrideAdd       OverrideAction = "add"
	OverrideRemove    OverrideAction = "remove"
	OverrideAIBlock   OverrideAction = "ai_block"
	OverrideAIUnblock OverrideAction = "ai_unblock"
)

type queryRower interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// upsertOverride writes one word's state with a fresh seq. Fields an action
// does not touch keep their current value (a new row starts present, unblocked).
func upsertOverride(ctx context.Context, q queryRower, word string, a OverrideAction) (DictOverride, error) {
	present, ai := true, false
	setPresent, setAI := true, true
	switch a {
	case OverrideAdd:
		// present, and a re-add keeps any AI block.
		setAI = false
	case OverrideRemove:
		present = false
	case OverrideAIBlock:
		ai, setPresent = true, false
	case OverrideAIUnblock:
		setPresent = false
	default:
		return DictOverride{}, fmt.Errorf("upsertOverride: unknown action %q", a)
	}
	const sqlText = `
		INSERT INTO dictionary_overrides (word, present, ai_blocked, seq)
		VALUES ($1, $2, $3, nextval('dictionary_overrides_seq'))
		ON CONFLICT (word) DO UPDATE SET
			present    = CASE WHEN $4::boolean THEN EXCLUDED.present ELSE dictionary_overrides.present END,
			ai_blocked = CASE WHEN $5::boolean THEN EXCLUDED.ai_blocked ELSE dictionary_overrides.ai_blocked END,
			seq        = EXCLUDED.seq,
			updated_at = now()
		RETURNING word, present, ai_blocked, seq, updated_at`
	var o DictOverride
	if err := q.QueryRowContext(ctx, sqlText, word, present, ai, setPresent, setAI).
		Scan(&o.Word, &o.Present, &o.AIBlocked, &o.Seq, &o.UpdatedAt); err != nil {
		return DictOverride{}, fmt.Errorf("upsertOverride %s: %w", a, err)
	}
	return o, nil
}

// SetOverride applies a direct dictionary change (no suggestion involved).
func (r *WordRepository) SetOverride(ctx context.Context, word string, a OverrideAction) (DictOverride, error) {
	return upsertOverride(ctx, r.db, word, a)
}

// WordReportInput is one player's report.
type WordReportInput struct {
	Word        string
	Kind        string
	ReporterKey string // "u:<user id>" or "i:<install id>"
	UserID      string // "" for a guest
	InstallID   string // "" when unknown
	Reason      string
}

// WordReportResult is the state of the suggestion after the report.
type WordReportResult struct {
	Status    string
	Reporters int
	Counted   bool // false when this reporter had already reported the word
}

// SubmitReport records a report, creating the suggestion on first sight. A
// suggestion that was already reviewed returns ErrSuggestionNotPending.
func (r *WordRepository) SubmitReport(ctx context.Context, in WordReportInput) (*WordReportResult, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SubmitReport begin: %w", err)
	}
	defer tx.Rollback()

	var id int64
	var status string
	err = tx.QueryRowContext(ctx, `
		INSERT INTO word_suggestions (word, kind) VALUES ($1, $2)
		ON CONFLICT (word, kind) DO UPDATE SET word = EXCLUDED.word
		RETURNING id, status`, in.Word, in.Kind).Scan(&id, &status)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SubmitReport upsert: %w", err)
	}
	if status != WordPending {
		return nil, ErrSuggestionNotPending
	}

	var userID, installID any
	if in.UserID != "" {
		userID = in.UserID
	}
	if in.InstallID != "" {
		installID = in.InstallID
	}
	res, err := tx.ExecContext(ctx, `
		INSERT INTO word_suggestion_reports (suggestion_id, reporter_key, user_id, install_id, reason)
		VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`, id, in.ReporterKey, userID, installID, in.Reason)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SubmitReport report: %w", err)
	}
	n, _ := res.RowsAffected()
	out := &WordReportResult{Status: status, Counted: n > 0}
	if out.Counted {
		err = tx.QueryRowContext(ctx, `
			UPDATE word_suggestions SET reporters = reporters + 1, last_reported_at = now()
			WHERE id = $1 RETURNING reporters`, id).Scan(&out.Reporters)
	} else {
		err = tx.QueryRowContext(ctx, `SELECT reporters FROM word_suggestions WHERE id = $1`, id).Scan(&out.Reporters)
	}
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SubmitReport count: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("WordRepository.SubmitReport commit: %w", err)
	}
	return out, nil
}

// MyWordReport is one of a player's own reports with its current status.
type MyWordReport struct {
	Word      string
	Kind      string
	Status    string
	Outcome   string
	Reason    string
	Rewarded  bool
	CreatedAt time.Time
}

// MyReports lists a signed-in player's reports, newest first.
func (r *WordRepository) MyReports(ctx context.Context, userID string, limit int) ([]MyWordReport, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT s.word, s.kind, s.status, s.outcome, r.reason, r.created_at,
		       EXISTS (SELECT 1 FROM inbox_rewards ir
		               WHERE ir.user_id = $1 AND ir.kind = $3 AND ir.ref = s.word)
		FROM word_suggestion_reports r JOIN word_suggestions s ON s.id = r.suggestion_id
		WHERE r.user_id = $1
		ORDER BY r.created_at DESC LIMIT $2`, userID, limit, RewardWordSuggestion)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.MyReports: %w", err)
	}
	defer rows.Close()
	out := []MyWordReport{}
	for rows.Next() {
		var m MyWordReport
		if err := rows.Scan(&m.Word, &m.Kind, &m.Status, &m.Outcome, &m.Reason, &m.CreatedAt, &m.Rewarded); err != nil {
			return nil, fmt.Errorf("WordRepository.MyReports scan: %w", err)
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// AdminWordSuggestion is a suggestion as the review queue lists it.
type AdminWordSuggestion struct {
	ID             int64
	Word           string
	Kind           string
	Status         string
	Outcome        string
	Reporters      int
	NotAWord       int // removal reports by reason
	Inappropriate  int
	ReviewNote     string
	ReviewedBy     string
	ReviewedAt     *time.Time
	CreatedAt      time.Time
	LastReportedAt time.Time
}

// WordListParams filters the review queue. Empty Status / Kind mean all.
type WordListParams struct {
	Status string
	Kind   string
	Query  string // substring of the word
	Recent bool   // newest report first instead of most reporters first
	Limit  int
	Offset int
}

const suggestionCols = `s.id, s.word, s.kind, s.status, s.outcome, s.reporters,
	(SELECT count(*) FROM word_suggestion_reports r WHERE r.suggestion_id = s.id AND r.reason = 'not_a_word'),
	(SELECT count(*) FROM word_suggestion_reports r WHERE r.suggestion_id = s.id AND r.reason = 'inappropriate'),
	s.review_note, s.reviewed_by, s.reviewed_at, s.created_at, s.last_reported_at`

func scanSuggestion(sc interface{ Scan(...any) error }) (AdminWordSuggestion, error) {
	var s AdminWordSuggestion
	err := sc.Scan(&s.ID, &s.Word, &s.Kind, &s.Status, &s.Outcome, &s.Reporters, &s.NotAWord, &s.Inappropriate,
		&s.ReviewNote, &s.ReviewedBy, &s.ReviewedAt, &s.CreatedAt, &s.LastReportedAt)
	return s, err
}

// ListSuggestions returns one page of the review queue and the total match count.
func (r *WordRepository) ListSuggestions(ctx context.Context, p WordListParams) ([]AdminWordSuggestion, int, error) {
	const where = `WHERE ($1 = '' OR s.status = $1) AND ($2 = '' OR s.kind = $2) AND ($3 = '' OR strpos(s.word, $3) > 0)`
	var total int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM word_suggestions s `+where, p.Status, p.Kind, p.Query).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("WordRepository.ListSuggestions count: %w", err)
	}
	order := `s.reporters DESC, s.last_reported_at DESC, s.id`
	if p.Recent {
		order = `s.last_reported_at DESC, s.id`
	}
	rows, err := r.db.QueryContext(ctx, `SELECT `+suggestionCols+` FROM word_suggestions s `+where+
		` ORDER BY `+order+` LIMIT $4 OFFSET $5`, p.Status, p.Kind, p.Query, p.Limit, p.Offset)
	if err != nil {
		return nil, 0, fmt.Errorf("WordRepository.ListSuggestions: %w", err)
	}
	defer rows.Close()
	out := []AdminWordSuggestion{}
	for rows.Next() {
		s, err := scanSuggestion(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("WordRepository.ListSuggestions scan: %w", err)
		}
		out = append(out, s)
	}
	return out, total, rows.Err()
}

// SuggestionCounts returns the pending queue sizes per kind.
func (r *WordRepository) SuggestionCounts(ctx context.Context) (map[string]int, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT kind, count(*) FROM word_suggestions WHERE status = 'pending' GROUP BY kind`)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SuggestionCounts: %w", err)
	}
	defer rows.Close()
	out := map[string]int{WordKindAdd: 0, WordKindRemove: 0}
	for rows.Next() {
		var k string
		var n int
		if err := rows.Scan(&k, &n); err != nil {
			return nil, fmt.Errorf("WordRepository.SuggestionCounts scan: %w", err)
		}
		out[k] = n
	}
	return out, rows.Err()
}

// AdminWordReport is one reporter of a suggestion.
type AdminWordReport struct {
	Username  string // "" for a guest
	UserID    string
	Reason    string
	CreatedAt time.Time
}

// GetSuggestion returns one suggestion with its reporters, oldest first.
func (r *WordRepository) GetSuggestion(ctx context.Context, id int64) (*AdminWordSuggestion, []AdminWordReport, error) {
	s, err := scanSuggestion(r.db.QueryRowContext(ctx, `SELECT `+suggestionCols+` FROM word_suggestions s WHERE s.id = $1`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, ErrSuggestionNotFound
	}
	if err != nil {
		return nil, nil, fmt.Errorf("WordRepository.GetSuggestion: %w", err)
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT COALESCE(u.username, ''), COALESCE(r.user_id::text, ''), r.reason, r.created_at
		FROM word_suggestion_reports r LEFT JOIN users u ON u.id = r.user_id
		WHERE r.suggestion_id = $1 ORDER BY r.created_at LIMIT 200`, id)
	if err != nil {
		return nil, nil, fmt.Errorf("WordRepository.GetSuggestion reports: %w", err)
	}
	defer rows.Close()
	reports := []AdminWordReport{}
	for rows.Next() {
		var a AdminWordReport
		if err := rows.Scan(&a.Username, &a.UserID, &a.Reason, &a.CreatedAt); err != nil {
			return nil, nil, fmt.Errorf("WordRepository.GetSuggestion reports scan: %w", err)
		}
		reports = append(reports, a)
	}
	return &s, reports, rows.Err()
}

// ApprovedWord is the result of approving a suggestion.
type ApprovedWord struct {
	Word          string
	Kind          string
	Outcome       string
	Override      DictOverride
	RewardUserID  string // "" when nobody earned a reward
	RewardCreated bool
}

// ApproveSuggestion approves a pending suggestion in one transaction: marks it
// reviewed, writes the dictionary override and, for an addition, creates the
// claimable reward for the first signed-in reporter. outcome is only used for
// removal suggestions (WordOutcomeRemove or WordOutcomeAIBlock).
func (r *WordRepository) ApproveSuggestion(ctx context.Context, id int64, admin, note, outcome string, rewardCoins int) (*ApprovedWord, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.ApproveSuggestion begin: %w", err)
	}
	defer tx.Rollback()

	var word, kind, status string
	err = tx.QueryRowContext(ctx, `SELECT word, kind, status FROM word_suggestions WHERE id = $1 FOR UPDATE`, id).Scan(&word, &kind, &status)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrSuggestionNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("WordRepository.ApproveSuggestion lock: %w", err)
	}
	if status != WordPending {
		return nil, ErrSuggestionNotPending
	}

	var action OverrideAction
	switch {
	case kind == WordKindAdd:
		outcome, action = WordOutcomeAdd, OverrideAdd
	case outcome == WordOutcomeRemove:
		action = OverrideRemove
	case outcome == WordOutcomeAIBlock:
		action = OverrideAIBlock
	default:
		return nil, ErrSuggestionOutcome
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE word_suggestions SET status = 'approved', outcome = $2, review_note = $3, reviewed_by = $4, reviewed_at = now()
		WHERE id = $1`, id, outcome, note, admin); err != nil {
		return nil, fmt.Errorf("WordRepository.ApproveSuggestion update: %w", err)
	}
	ov, err := upsertOverride(ctx, tx, word, action)
	if err != nil {
		return nil, err
	}
	out := &ApprovedWord{Word: word, Kind: kind, Outcome: outcome, Override: ov}

	if kind == WordKindAdd {
		var uid string
		err := tx.QueryRowContext(ctx, `
			SELECT user_id FROM word_suggestion_reports
			WHERE suggestion_id = $1 AND user_id IS NOT NULL ORDER BY created_at LIMIT 1`, id).Scan(&uid)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("WordRepository.ApproveSuggestion reporter: %w", err)
		}
		if uid != "" {
			res, err := tx.ExecContext(ctx, `
				INSERT INTO inbox_rewards (user_id, kind, ref, detail, coins) VALUES ($1, $2, $3, $3, $4)
				ON CONFLICT (user_id, kind, ref) DO NOTHING`, uid, RewardWordSuggestion, word, rewardCoins)
			if err != nil {
				return nil, fmt.Errorf("WordRepository.ApproveSuggestion reward: %w", err)
			}
			n, _ := res.RowsAffected()
			out.RewardUserID, out.RewardCreated = uid, n > 0
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("WordRepository.ApproveSuggestion commit: %w", err)
	}
	return out, nil
}

// RejectSuggestion turns a pending suggestion down and returns its word.
func (r *WordRepository) RejectSuggestion(ctx context.Context, id int64, admin, note string) (string, error) {
	var word string
	err := r.db.QueryRowContext(ctx, `
		UPDATE word_suggestions SET status = 'rejected', review_note = $2, reviewed_by = $3, reviewed_at = now()
		WHERE id = $1 AND status = 'pending' RETURNING word`, id, note, admin).Scan(&word)
	if errors.Is(err, sql.ErrNoRows) {
		var exists bool
		if qerr := r.db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM word_suggestions WHERE id = $1)`, id).Scan(&exists); qerr != nil {
			return "", fmt.Errorf("WordRepository.RejectSuggestion exists: %w", qerr)
		}
		if !exists {
			return "", ErrSuggestionNotFound
		}
		return "", ErrSuggestionNotPending
	}
	if err != nil {
		return "", fmt.Errorf("WordRepository.RejectSuggestion: %w", err)
	}
	return word, nil
}

// WordSuggestionStatus returns the status of a (word, kind) suggestion, or ""
// when nobody has reported it.
func (r *WordRepository) WordSuggestionStatus(ctx context.Context, word, kind string) (string, error) {
	var st string
	err := r.db.QueryRowContext(ctx, `SELECT status FROM word_suggestions WHERE word = $1 AND kind = $2`, word, kind).Scan(&st)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("WordRepository.WordSuggestionStatus: %w", err)
	}
	return st, nil
}

// SuggestionsForWord lists every suggestion about a word (lookup page).
func (r *WordRepository) SuggestionsForWord(ctx context.Context, word string) ([]AdminWordSuggestion, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT `+suggestionCols+` FROM word_suggestions s WHERE s.word = $1 ORDER BY s.kind`, word)
	if err != nil {
		return nil, fmt.Errorf("WordRepository.SuggestionsForWord: %w", err)
	}
	defer rows.Close()
	out := []AdminWordSuggestion{}
	for rows.Next() {
		s, err := scanSuggestion(rows)
		if err != nil {
			return nil, fmt.Errorf("WordRepository.SuggestionsForWord scan: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
