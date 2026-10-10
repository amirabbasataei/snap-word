package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/engine"
	"wordchain/backend/internal/repository"
)

// Sentinel errors of the admin content endpoints; the handler maps them to codes.
var (
	ErrInvalidDate      = errors.New("invalid date")
	ErrInvalidLetter    = errors.New("invalid start letter")
	ErrDailyNotEditable = errors.New("daily challenge not editable")
	ErrNoChallenge      = errors.New("no daily challenge for date")
	ErrInvalidLimit     = errors.New("invalid limit")
)

// Limits for the admin content endpoints.
const (
	adminDailyDefaultPast    = 29 // list window: today-29 …
	adminDailyDefaultFuture  = 7  // … today+7
	adminDailyMaxSpanDays    = 120
	AdminDailyMaxFutureDays  = 60 // how far ahead a start letter may be scheduled
	adminDailyBoardLimit     = 100
	adminDailyAttemptLimit   = 100
	adminBoardDefaultLimit   = 50
	adminBoardMaxLimit       = 100
	adminRewardsDefaultWeeks = 8
	adminRewardsMaxWeeks     = 52
)

// ReasonFor validates the audit reason of an action that panel sessions must
// justify; the X-Admin-Key script (no admin id) may leave it empty.
func ReasonFor(actor AuditActor, raw string) (string, error) {
	if actor.AdminID == "" && strings.TrimSpace(raw) == "" {
		return "", nil
	}
	return cleanReason(raw)
}

type adminContentStore interface {
	ListTauntsAdmin(ctx context.Context) ([]repository.AdminTaunt, error)
	ListAvatarsAdmin(ctx context.Context) ([]repository.AdminAvatar, error)
	AvatarUsage(ctx context.Context, id string) (users, active int, err error)
	ListDaily(ctx context.Context, from, to time.Time) ([]repository.AdminDailyRow, error)
	DailyStats(ctx context.Context, date time.Time) (repository.AdminDailyStats, error)
	DailyAttempts(ctx context.Context, date time.Time, limit int) ([]repository.AdminDayAttempt, error)
	DailyRewards(ctx context.Context, date time.Time) (repository.AdminDailyRewards, error)
	SetDailyStartLetter(ctx context.Context, date time.Time, seed int64, letter string, today time.Time) error
	WeeklyRewards(ctx context.Context, weeks int) ([]repository.AdminWeeklyReward, error)
}

type adminDailyReader interface {
	GetChallenge(ctx context.Context, date time.Time) (*repository.DailyChallengeRow, error)
	GetDailyLeaderboard(ctx context.Context, date time.Time, limit int) ([]*repository.DailyBoardRow, error)
}

type adminBoards interface {
	GetTopN(ctx context.Context, n int) ([]LeaderboardEntry, error)
	GetAllTimeTop(ctx context.Context, n int) ([]LeaderboardEntry, error)
}

type adminBannedLookup interface {
	BannedIDs(ctx context.Context, userIDs []string) (map[string]struct{}, error)
}

// AdminContentService backs the panel's content pages: the taunt and avatar
// catalogues (reads), the Daily Challenge calendar and the leaderboards. The
// catalogue writes live in CatalogService; only the start-letter change is
// written (and audited) here.
type AdminContentService struct {
	store  adminContentStore
	daily  adminDailyReader
	boards adminBoards
	banned adminBannedLookup
	rdb    redis.Cmdable
	audit  *AuditService
	epoch  time.Time
	now    func() time.Time
}

func NewAdminContentService(
	store adminContentStore, daily adminDailyReader, boards adminBoards, banned adminBannedLookup,
	rdb redis.Cmdable, audit *AuditService, cfg *config.Config,
) (*AdminContentService, error) {
	epoch, err := time.Parse("2006-01-02", cfg.GameEpochDate)
	if err != nil {
		return nil, fmt.Errorf("parse GAME_EPOCH_DATE: %w", err)
	}
	return &AdminContentService{
		store: store, daily: daily, boards: boards, banned: banned, rdb: rdb, audit: audit,
		epoch: epoch, now: time.Now,
	}, nil
}

// ---- catalogues ----

type TauntItem struct {
	ID        string `json:"id"`
	Text      string `json:"text"`
	SortOrder int    `json:"sort_order"`
}

type TauntList struct {
	Items        []TauntItem `json:"items"`
	MaxTextRunes int         `json:"max_text_runes"`
}

// Taunts lists the taunts in picker order, read straight from the table.
func (s *AdminContentService) Taunts(ctx context.Context) (*TauntList, error) {
	rows, err := s.store.ListTauntsAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.Taunts: %w", err)
	}
	out := &TauntList{Items: make([]TauntItem, len(rows)), MaxTextRunes: config.TauntMaxTextRunes}
	for i, t := range rows {
		out.Items[i] = TauntItem{ID: t.ID, Text: t.Text, SortOrder: t.SortOrder}
	}
	return out, nil
}

type AvatarItem struct {
	ID          string    `json:"id"`
	SortOrder   int       `json:"sort_order"`
	ContentType string    `json:"content_type"`
	Bytes       int       `json:"bytes"`
	UpdatedAt   time.Time `json:"updated_at"`
	Users       int       `json:"users"`
	ActiveUsers int       `json:"active_users"`
}

type AvatarList struct {
	Items    []AvatarItem `json:"items"`
	MaxBytes int          `json:"max_bytes"`
	Types    []string     `json:"types"`
}

// Avatars lists the avatars (no image bytes) in picker order with usage counts.
func (s *AdminContentService) Avatars(ctx context.Context) (*AvatarList, error) {
	rows, err := s.store.ListAvatarsAdmin(ctx)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.Avatars: %w", err)
	}
	out := &AvatarList{
		Items:    make([]AvatarItem, len(rows)),
		MaxBytes: config.AvatarMaxBytes,
		Types:    []string{"image/png", "image/jpeg", "image/webp"},
	}
	for i, a := range rows {
		out.Items[i] = AvatarItem{ID: a.ID, SortOrder: a.SortOrder, ContentType: a.ContentType, Bytes: a.Bytes,
			UpdatedAt: a.UpdatedAt, Users: a.Users, ActiveUsers: a.ActiveUsers}
	}
	return out, nil
}

type AvatarUsageResult struct {
	ID          string `json:"id"`
	Users       int    `json:"users"`
	ActiveUsers int    `json:"active_users"`
}

// AvatarUsage reports how many users currently have the avatar picked (and how
// many of them are premium, i.e. actually show it).
func (s *AdminContentService) AvatarUsage(ctx context.Context, id string) (*AvatarUsageResult, error) {
	users, active, err := s.store.AvatarUsage(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.AvatarUsage: %w", err)
	}
	return &AvatarUsageResult{ID: id, Users: users, ActiveUsers: active}, nil
}

// ---- daily challenge ----

const dateLayout = "2006-01-02"

func (s *AdminContentService) today() time.Time { return config.IranDate(s.now()) }

func (s *AdminContentService) dayNumber(date time.Time) int {
	return int(date.Sub(s.epoch).Hours()/24) + 1
}

func parseAdminDate(raw string) (time.Time, error) {
	d, err := time.Parse(dateLayout, raw)
	if err != nil {
		return time.Time{}, ErrInvalidDate
	}
	return d, nil
}

func dayStatus(date, today time.Time) string {
	switch {
	case date.Before(today):
		return "past"
	case date.Equal(today):
		return "today"
	default:
		return "future"
	}
}

type DailyDay struct {
	Date string `json:"date"`
	// DayNumber is the share-card "Daily #N" (days since GAME_EPOCH_DATE, 1-indexed).
	DayNumber   int    `json:"day_number"`
	StartLetter string `json:"start_letter"`
	// Generated is false for a future day the scheduler has not created yet; its
	// StartLetter is then the one it will generate (Seed is the date's default seed).
	Generated bool `json:"generated"`
	// Customized marks a letter that differs from the one the seed generates.
	Customized bool   `json:"customized"`
	Status     string `json:"status"` // past | today | future
	Editable   bool   `json:"editable"`
	Players    int    `json:"players"`
	Attempts   int    `json:"attempts"`
	BestScore  int    `json:"best_score"`
}

type DailyList struct {
	From            string     `json:"from"`
	To              string     `json:"to"`
	Today           string     `json:"today"`
	EligibleLetters []string   `json:"eligible_letters"`
	Rows            []DailyDay `json:"rows"`
}

func (s *AdminContentService) dailyDay(date time.Time, row *repository.AdminDailyRow, today time.Time) DailyDay {
	d := DailyDay{
		Date:      date.Format(dateLayout),
		DayNumber: s.dayNumber(date),
		Status:    dayStatus(date, today),
		Editable:  date.After(today),
	}
	seed := date.Unix()
	if row != nil {
		seed = row.Seed
		d.Generated = true
		d.StartLetter = row.StartLetter
		d.Players, d.Attempts, d.BestScore = row.Players, row.Attempts, row.BestScore
	} else {
		d.StartLetter = engine.PickDailyStartLetter(seed)
	}
	d.Customized = d.StartLetter != engine.PickDailyStartLetter(seed)
	return d
}

// DailyCalendar lists challenge days from..to (inclusive; defaults today-29 …
// today+7). Past days appear only if they were generated; future days always
// appear, showing the letter that will be generated unless one was scheduled.
func (s *AdminContentService) DailyCalendar(ctx context.Context, fromRaw, toRaw string) (*DailyList, error) {
	today := s.today()
	from, to := today.AddDate(0, 0, -adminDailyDefaultPast), today.AddDate(0, 0, adminDailyDefaultFuture)
	var err error
	if fromRaw != "" {
		if from, err = parseAdminDate(fromRaw); err != nil {
			return nil, err
		}
	}
	if toRaw != "" {
		if to, err = parseAdminDate(toRaw); err != nil {
			return nil, err
		}
	}
	if to.Before(from) || to.Sub(from) > adminDailyMaxSpanDays*24*time.Hour ||
		to.After(today.AddDate(0, 0, AdminDailyMaxFutureDays)) {
		return nil, ErrInvalidDate
	}

	rows, err := s.store.ListDaily(ctx, from, to)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.DailyCalendar: %w", err)
	}
	byDate := make(map[string]*repository.AdminDailyRow, len(rows))
	for i := range rows {
		byDate[rows[i].Date.Format(dateLayout)] = &rows[i]
	}

	out := &DailyList{
		From: from.Format(dateLayout), To: to.Format(dateLayout), Today: today.Format(dateLayout),
		EligibleLetters: engine.DailyStartLetters(), Rows: []DailyDay{},
	}
	for d := to; !d.Before(from); d = d.AddDate(0, 0, -1) {
		row := byDate[d.Format(dateLayout)]
		if row == nil && !d.After(today) {
			continue // a past day that was never generated
		}
		out.Rows = append(out.Rows, s.dailyDay(d, row, today))
	}
	return out, nil
}

type DailyBoardItem struct {
	Rank        int    `json:"rank"`
	UserID      string `json:"user_id"`
	Username    string `json:"username"`
	Score       int    `json:"score"`
	ChainLength int    `json:"chain_length"`
	Banned      bool   `json:"banned"`
}

type DailyAttemptItem struct {
	UserID      string    `json:"user_id"`
	Username    string    `json:"username"`
	Attempt     int       `json:"attempt"`
	Score       int       `json:"score"`
	ChainLength int       `json:"chain_length"`
	WordChain   []string  `json:"word_chain"`
	CompletedAt time.Time `json:"completed_at"`
}

type DailyPayout struct {
	// State: not_due (day not over) | no_players | paid (a completion reward
	// exists for every player) | pending (yesterday, not yet run — the scheduler
	// pays within minutes) | missed (unpaid, and the scheduler will not retry:
	// it only ever pays yesterday, once).
	State   string `json:"state"`
	Flagged bool   `json:"flagged"` // the scheduler's Redis flag payout:daily:<date>
	Rewards struct {
		DoneCreated int `json:"done_created"`
		DoneClaimed int `json:"done_claimed"`
		RankCreated int `json:"rank_created"`
		RankClaimed int `json:"rank_claimed"`
		Coins       int `json:"coins"`
	} `json:"rewards"`
}

type DailyDetail struct {
	DailyDay
	Seed            int64    `json:"seed"`
	EligibleLetters []string `json:"eligible_letters"`
	Stats           struct {
		Players   int     `json:"players"`
		Attempts  int     `json:"attempts"`
		Retries   int     `json:"retries"`
		BestScore int     `json:"best_score"`
		AvgScore  float64 `json:"avg_score"`
	} `json:"stats"`
	Board    []DailyBoardItem   `json:"board"`
	Attempts []DailyAttemptItem `json:"attempts"`
	Payout   DailyPayout        `json:"payout"`
}

// DailyDetail returns one generated day: its stats, ranking (best score per
// player — the same query the app's board and the payout use), newest attempts
// and payout status.
func (s *AdminContentService) DailyDetail(ctx context.Context, dateRaw string) (*DailyDetail, error) {
	date, err := parseAdminDate(dateRaw)
	if err != nil {
		return nil, err
	}
	ch, err := s.daily.GetChallenge(ctx, date)
	if errors.Is(err, repository.ErrNoDailyChallenge) {
		return nil, ErrNoChallenge
	}
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.DailyDetail: %w", err)
	}
	today := s.today()
	row := repository.AdminDailyRow{Date: date, Seed: ch.Seed, StartLetter: ch.StartLetter}
	stats, err := s.store.DailyStats(ctx, date)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.DailyDetail: %w", err)
	}
	row.Players, row.Attempts, row.BestScore = stats.Players, stats.Attempts, stats.BestScore

	out := &DailyDetail{DailyDay: s.dailyDay(date, &row, today), Seed: ch.Seed, EligibleLetters: engine.DailyStartLetters()}
	out.Stats.Players, out.Stats.Attempts, out.Stats.Retries = stats.Players, stats.Attempts, stats.Retries
	out.Stats.BestScore, out.Stats.AvgScore = stats.BestScore, stats.AvgScore

	board, err := s.daily.GetDailyLeaderboard(ctx, date, adminDailyBoardLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.DailyDetail: %w", err)
	}
	ids := make([]string, len(board))
	for i, b := range board {
		ids[i] = b.UserID
	}
	banned := map[string]struct{}{}
	if len(ids) > 0 {
		if banned, err = s.banned.BannedIDs(ctx, ids); err != nil {
			return nil, fmt.Errorf("AdminContentService.DailyDetail banned: %w", err)
		}
	}
	out.Board = make([]DailyBoardItem, len(board))
	for i, b := range board {
		_, isBanned := banned[b.UserID]
		out.Board[i] = DailyBoardItem{Rank: b.Rank, UserID: b.UserID, Username: b.Username, Score: b.Score,
			ChainLength: b.ChainLength, Banned: isBanned}
	}

	attempts, err := s.store.DailyAttempts(ctx, date, adminDailyAttemptLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.DailyDetail: %w", err)
	}
	out.Attempts = make([]DailyAttemptItem, len(attempts))
	for i, a := range attempts {
		out.Attempts[i] = DailyAttemptItem{UserID: a.UserID, Username: a.Username, Attempt: a.Attempt, Score: a.Score,
			ChainLength: a.ChainLength, WordChain: a.WordChain, CompletedAt: a.CompletedAt}
	}

	if out.Payout, err = s.payout(ctx, date, today, stats.Players); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *AdminContentService) payout(ctx context.Context, date, today time.Time, players int) (DailyPayout, error) {
	var p DailyPayout
	rewards, err := s.store.DailyRewards(ctx, date)
	if err != nil {
		return p, fmt.Errorf("AdminContentService.payout: %w", err)
	}
	p.Rewards.DoneCreated, p.Rewards.DoneClaimed = rewards.DoneCreated, rewards.DoneClaimed
	p.Rewards.RankCreated, p.Rewards.RankClaimed = rewards.RankCreated, rewards.RankClaimed
	p.Rewards.Coins = rewards.CoinsCreated

	if n, err := s.rdb.Exists(ctx, "payout:daily:"+date.Format(dateLayout)).Result(); err != nil {
		return p, fmt.Errorf("AdminContentService.payout flag: %w", err)
	} else {
		p.Flagged = n > 0
	}
	switch {
	case !date.Before(today):
		p.State = "not_due"
	case players == 0:
		p.State = "no_players"
	case rewards.DoneCreated >= players:
		p.State = "paid" // the reward rows are the truth; the Redis flag may predate late attempts
	case !p.Flagged && date.Equal(today.AddDate(0, 0, -1)):
		p.State = "pending"
	default:
		p.State = "missed" // the scheduler pays each day once and only ever yesterday
	}
	return p, nil
}

type StartLetterResult struct {
	Date        string `json:"date"`
	StartLetter string `json:"start_letter"`
	Previous    string `json:"previous"`
	Created     bool   `json:"created"`
}

// SetStartLetter changes the start letter of a future day (creating its row if
// the scheduler has not yet — the day then keeps date.Unix() as seed, exactly
// as EnsureChallenge would have stored it). Today and past days are locked:
// players are already playing, or have played, them.
func (s *AdminContentService) SetStartLetter(ctx context.Context, actor AuditActor, dateRaw, letter, reason string) (*StartLetterResult, error) {
	reason, err := cleanReason(reason)
	if err != nil {
		return nil, err
	}
	date, err := parseAdminDate(dateRaw)
	if err != nil {
		return nil, err
	}
	today := s.today()
	if !date.After(today) {
		return nil, ErrDailyNotEditable
	}
	if date.After(today.AddDate(0, 0, AdminDailyMaxFutureDays)) {
		return nil, ErrInvalidDate
	}
	letter = strings.TrimSpace(letter)
	if !engine.IsDailyStartLetter(letter) {
		return nil, ErrInvalidLetter
	}

	previous, seed, created := engine.PickDailyStartLetter(date.Unix()), date.Unix(), true
	switch ch, err := s.daily.GetChallenge(ctx, date); {
	case err == nil:
		previous, seed, created = ch.StartLetter, ch.Seed, false
	case !errors.Is(err, repository.ErrNoDailyChallenge):
		return nil, fmt.Errorf("AdminContentService.SetStartLetter: %w", err)
	}

	if err := s.store.SetDailyStartLetter(ctx, date, seed, letter, today); err != nil {
		if errors.Is(err, repository.ErrDailyLocked) {
			return nil, ErrDailyNotEditable
		}
		return nil, fmt.Errorf("AdminContentService.SetStartLetter: %w", err)
	}
	dateStr := date.Format(dateLayout)
	s.audit.LogRecord(ctx, actor, "daily.start_letter", AuditTarget{Type: "daily", ID: dateStr}, map[string]any{
		"before": previous, "after": letter, "created": created, "reason": reason,
	})
	return &StartLetterResult{Date: dateStr, StartLetter: letter, Previous: previous, Created: created}, nil
}

// ---- leaderboards ----

type BoardEntry struct {
	Rank     int     `json:"rank"`
	UserID   string  `json:"user_id"`
	Username string  `json:"username"`
	Score    float64 `json:"score"`
	AvatarID string  `json:"avatar_id"`
}

type Board struct {
	Entries []BoardEntry `json:"entries"`
	Limit   int          `json:"limit"`
	// ResetsAt is the next weekly payout/reset (weekly board only).
	ResetsAt *time.Time `json:"resets_at,omitempty"`
}

func cleanBoardLimit(limit int) (int, error) {
	if limit == 0 {
		return adminBoardDefaultLimit, nil
	}
	if limit < 1 || limit > adminBoardMaxLimit {
		return 0, ErrInvalidLimit
	}
	return limit, nil
}

func toBoard(entries []LeaderboardEntry, limit int) *Board {
	b := &Board{Entries: make([]BoardEntry, len(entries)), Limit: limit}
	for i, e := range entries {
		b.Entries[i] = BoardEntry{Rank: e.Rank, UserID: e.UserID, Username: e.Username, Score: e.Score, AvatarID: e.AvatarID}
	}
	return b
}

// nextWeeklyReset is the next Saturday 00:00 Iran time strictly after now.
func nextWeeklyReset(now time.Time) time.Time {
	l := now.In(config.IranLocation)
	ahead := (int(time.Saturday) - int(l.Weekday()) + 7) % 7
	if ahead == 0 {
		ahead = 7
	}
	return time.Date(l.Year(), l.Month(), l.Day()+ahead, 0, 0, 0, 0, config.IranLocation)
}

// WeeklyBoard is this week's board; banned players are dropped, as in the app.
func (s *AdminContentService) WeeklyBoard(ctx context.Context, limit int) (*Board, error) {
	limit, err := cleanBoardLimit(limit)
	if err != nil {
		return nil, err
	}
	entries, err := s.boards.GetTopN(ctx, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.WeeklyBoard: %w", err)
	}
	b := toBoard(entries, limit)
	reset := nextWeeklyReset(s.now())
	b.ResetsAt = &reset
	return b, nil
}

// AllTimeBoard is the lifetime board; banned players are excluded in SQL.
func (s *AdminContentService) AllTimeBoard(ctx context.Context, limit int) (*Board, error) {
	limit, err := cleanBoardLimit(limit)
	if err != nil {
		return nil, err
	}
	entries, err := s.boards.GetAllTimeTop(ctx, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.AllTimeBoard: %w", err)
	}
	return toBoard(entries, limit), nil
}

type WeeklyRewardItem struct {
	Rank      int       `json:"rank"`
	UserID    string    `json:"user_id"`
	Username  string    `json:"username"`
	Coins     int       `json:"coins"`
	AwardedAt time.Time `json:"awarded_at"`
	Banned    bool      `json:"banned"`
}

type WeeklyRewardWeek struct {
	// PayoutDate is the Saturday the prizes were paid (weekly_leaderboard_rewards.week_start).
	PayoutDate string             `json:"payout_date"`
	Rewards    []WeeklyRewardItem `json:"rewards"`
}

type WeeklyRewardHistory struct {
	Weeks  []WeeklyRewardWeek `json:"weeks"`
	Prizes []int              `json:"prizes"` // the current prize table, rank 1..3
}

// WeeklyRewardHistory lists the paid weekly prizes of the latest `weeks` payouts.
func (s *AdminContentService) WeeklyRewardHistory(ctx context.Context, weeks int) (*WeeklyRewardHistory, error) {
	if weeks == 0 {
		weeks = adminRewardsDefaultWeeks
	}
	if weeks < 1 || weeks > adminRewardsMaxWeeks {
		return nil, ErrInvalidLimit
	}
	rows, err := s.store.WeeklyRewards(ctx, weeks)
	if err != nil {
		return nil, fmt.Errorf("AdminContentService.WeeklyRewardHistory: %w", err)
	}
	out := &WeeklyRewardHistory{
		Weeks:  []WeeklyRewardWeek{},
		Prizes: []int{config.CoinWeeklyRank1, config.CoinWeeklyRank2, config.CoinWeeklyRank3},
	}
	for _, r := range rows {
		date := r.WeekStart.Format(dateLayout)
		if n := len(out.Weeks); n == 0 || out.Weeks[n-1].PayoutDate != date {
			out.Weeks = append(out.Weeks, WeeklyRewardWeek{PayoutDate: date, Rewards: []WeeklyRewardItem{}})
		}
		w := &out.Weeks[len(out.Weeks)-1]
		w.Rewards = append(w.Rewards, WeeklyRewardItem{Rank: r.Rank, UserID: r.UserID, Username: r.Username,
			Coins: r.Coins, AwardedAt: r.AwardedAt, Banned: r.Banned})
	}
	return out, nil
}
