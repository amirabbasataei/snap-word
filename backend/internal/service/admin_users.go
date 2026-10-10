package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// Sentinel errors for the admin user endpoints; the handler maps them to codes.
var (
	ErrUserNotFound   = errors.New("user not found")
	ErrReasonRequired = errors.New("reason required")
	ErrInvalidAmount  = errors.New("invalid coin amount")
	ErrInvalidDays    = errors.New("invalid premium days")
	ErrInvalidSort    = errors.New("invalid sort")
	ErrInvalidFilter  = errors.New("invalid filter")
	ErrAlreadyBanned  = repository.ErrAlreadyBanned
	ErrNotBanned      = repository.ErrNotBanned
)

// Limits for the admin user endpoints.
const (
	AdminUsersDefaultPageSize = 25
	AdminUsersMaxPageSize     = 100
	AdminMaxCoinAdjust        = 1_000_000
	AdminMaxPremiumDays       = 3650
	AdminReasonMinRunes       = 3
	AdminReasonMaxRunes       = 200
	adminNewUserDays          = 7
	adminDetailListLimit      = 50
	adminDetailMatchLimit     = 20
	adminDetailDailyLimit     = 14
)

// Coin grant modes.
const (
	CoinModeDirect = "direct" // change the balance right now (± amount)
	CoinModeReward = "reward" // create a claimable inbox reward (+ amount)
)

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

type adminUserStore interface {
	ListUsers(ctx context.Context, p repository.AdminUserListParams) ([]repository.AdminUserRow, int, error)
	GetUserDetail(ctx context.Context, id string) (*repository.AdminUserDetail, error)
	UserReferred(ctx context.Context, id string, limit int) ([]repository.AdminReferred, error)
	UserRewards(ctx context.Context, id string, limit int) ([]repository.AdminReward, error)
	UserMatches(ctx context.Context, id string, limit int) ([]repository.AdminUserMatch, error)
	UserDailyAttempts(ctx context.Context, id string, limit int) ([]repository.AdminDailyAttempt, error)
	AdjustCoins(ctx context.Context, id string, delta int) (int, error)
	ExtendPremium(ctx context.Context, id string, days int) (time.Time, error)
	RevokePremium(ctx context.Context, id string) error
	ClearAvatar(ctx context.Context, id string) (string, error)
	BanUser(ctx context.Context, id, reason string) error
	UnbanUser(ctx context.Context, id string) error
}

type adminRewardGranter interface {
	CreateInboxReward(ctx context.Context, userID, kind, ref, detail string, coins int) (bool, error)
}

type adminRenamer interface {
	UpdateUsername(ctx context.Context, userID, username string) (string, error)
}

// AdminUserService backs the panel's users pages: search, the user detail page
// and the audited actions (coins, premium, rename, avatar, ban).
type AdminUserService struct {
	store   adminUserStore
	rewards adminRewardGranter
	renamer adminRenamer
	audit   *AuditService
	now     func() time.Time
}

func NewAdminUserService(store adminUserStore, rewards adminRewardGranter, renamer adminRenamer, audit *AuditService) *AdminUserService {
	return &AdminUserService{store: store, rewards: rewards, renamer: renamer, audit: audit, now: time.Now}
}

// CanSeePhone reports whether a role may see unmasked phone numbers.
func CanSeePhone(role string) bool { return role == AdminRoleOwner }

// MaskPhone hides the middle of an Iranian mobile number (09121234567 → 0912*****67).
func MaskPhone(phone string) string {
	r := []rune(phone)
	if len(r) < 8 {
		return strings.Repeat("*", len(r))
	}
	return string(r[:4]) + strings.Repeat("*", len(r)-6) + string(r[len(r)-2:])
}

// UserListQuery is the validated query of GET /admin/users.
type UserListQuery struct {
	Q        string
	Filter   string
	Sort     string // created | coins | xp | matches | username
	Desc     bool
	Page     int
	PageSize int
}

// AdminUserItem is one row of the users table.
type AdminUserItem struct {
	ID           string     `json:"id"`
	Username     string     `json:"username"`
	Phone        string     `json:"phone"`
	PhoneMasked  bool       `json:"phone_masked"`
	Coins        int        `json:"coins"`
	XP           int64      `json:"xp"`
	Level        int        `json:"level"`
	TotalMatches int        `json:"total_matches"`
	Premium      bool       `json:"premium"`
	PremiumUntil *time.Time `json:"premium_until"`
	AvatarID     string     `json:"avatar_id"`
	CreatedAt    time.Time  `json:"created_at"`
	Banned       bool       `json:"banned"`
	BannedAt     *time.Time `json:"banned_at"`
}

// AdminUserPage is a page of the users table.
type AdminUserPage struct {
	Items    []AdminUserItem `json:"items"`
	Total    int             `json:"total"`
	Page     int             `json:"page"`
	PageSize int             `json:"page_size"`
}

func (s *AdminUserService) item(r repository.AdminUserRow, role string) AdminUserItem {
	phone := r.Phone
	if !CanSeePhone(role) {
		phone = MaskPhone(phone)
	}
	return AdminUserItem{
		ID: r.ID, Username: r.Username, Phone: phone, PhoneMasked: !CanSeePhone(role),
		Coins: r.Coins, XP: r.XP, Level: config.LevelFromXP(r.XP), TotalMatches: r.TotalMatches,
		Premium:      r.PremiumUntil != nil && r.PremiumUntil.After(s.now()),
		PremiumUntil: r.PremiumUntil, AvatarID: r.AvatarID, CreatedAt: r.CreatedAt,
		Banned: r.BannedAt != nil, BannedAt: r.BannedAt,
	}
}

// List searches and pages the users table. Only owners may search by phone
// number: for everyone else a phone fragment would act as an oracle that
// reveals digits the response masks.
func (s *AdminUserService) List(ctx context.Context, role string, q UserListQuery) (*AdminUserPage, error) {
	switch q.Filter {
	case "", repository.AdminFilterPremium, repository.AdminFilterBanned, repository.AdminFilterNew:
	default:
		return nil, ErrInvalidFilter
	}
	if q.Sort == "" {
		q.Sort = "created"
	}
	if !repository.AdminUserSortable(q.Sort) {
		return nil, ErrInvalidSort
	}
	if q.Page < 1 {
		q.Page = 1
	}
	if q.PageSize < 1 {
		q.PageSize = AdminUsersDefaultPageSize
	}
	if q.PageSize > AdminUsersMaxPageSize {
		q.PageSize = AdminUsersMaxPageSize
	}

	text := strings.TrimSpace(q.Q)
	p := repository.AdminUserListParams{
		Query: text, Filter: q.Filter, SortColumn: q.Sort, Desc: q.Desc,
		Page: q.Page, PageSize: q.PageSize, ExcludeID: config.SystemAIUserID,
		NewSince: s.now().AddDate(0, 0, -adminNewUserDays),
	}
	if CanSeePhone(role) {
		if digits := phoneFragment(text); digits != "" {
			p.PhoneDigits = digits
		}
	}

	rows, total, err := s.store.ListUsers(ctx, p)
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.List: %w", err)
	}
	out := &AdminUserPage{Items: make([]AdminUserItem, len(rows)), Total: total, Page: q.Page, PageSize: q.PageSize}
	for i, r := range rows {
		out.Items[i] = s.item(r, role)
	}
	return out, nil
}

// phoneFragment returns text as ASCII digits when it consists only of digits
// (Persian or Latin) and is long enough to be worth matching; otherwise "".
func phoneFragment(text string) string {
	digits := convertToASCIIDigits(strings.ReplaceAll(text, " ", ""))
	if len(digits) < 3 {
		return ""
	}
	for _, r := range digits {
		if r < '0' || r > '9' {
			return ""
		}
	}
	return digits
}

// AdminUserDetail is the whole user page in one payload.
type AdminUserDetail struct {
	AdminUserItem
	ReferralCode  string         `json:"referral_code"`
	BanReason     string         `json:"ban_reason"`
	JoinedAt      *time.Time     `json:"joined_at"`
	XPInLevel     int64          `json:"xp_in_level"`
	XPForNext     int64          `json:"xp_for_next"`
	Stats         userStatsView  `json:"stats"`
	FriendsCount  int            `json:"friends_count"`
	DeviceTokens  int            `json:"device_tokens"`
	Referrer      *userRef       `json:"referrer"`
	ReferredCount int            `json:"referred_count"`
	Referred      []referredView `json:"referred"`
	Rewards       []rewardView   `json:"rewards"`
	Matches       []matchView    `json:"matches"`
	DailyAttempts []dailyView    `json:"daily_attempts"`
}

type userStatsView struct {
	TotalMatches       int        `json:"total_matches"`
	Wins               int        `json:"wins"`
	LongestWord        string     `json:"longest_word"`
	BestMatchStreak    int        `json:"best_match_streak"`
	DailyStreak        int        `json:"daily_streak"`
	LongestDailyStreak int        `json:"longest_daily_streak"`
	LastPlayedDate     *time.Time `json:"last_played_date"`
	TotalScore         int64      `json:"total_score"`
}

type userRef struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

type referredView struct {
	ID        string    `json:"id"`
	Username  string    `json:"username"`
	CreatedAt time.Time `json:"created_at"`
}

type rewardView struct {
	ID        string     `json:"id"`
	Kind      string     `json:"kind"`
	Detail    string     `json:"detail"`
	Coins     int        `json:"coins"`
	Claimed   bool       `json:"claimed"`
	ClaimedAt *time.Time `json:"claimed_at"`
	CreatedAt time.Time  `json:"created_at"`
}

type matchView struct {
	ID          string     `json:"id"`
	Mode        string     `json:"mode"`
	Status      string     `json:"status"`
	Kind        string     `json:"kind"`
	Score       int        `json:"score"`
	Won         bool       `json:"won"`
	At          time.Time  `json:"at"`
	EndedAt     *time.Time `json:"ended_at"`
	PlayerCount int        `json:"player_count"`
}

type dailyView struct {
	Date        string    `json:"date"`
	Attempt     int       `json:"attempt"`
	Score       int       `json:"score"`
	ChainLength int       `json:"chain_length"`
	CompletedAt time.Time `json:"completed_at"`
}

func validUserID(id string) bool { return uuidRe.MatchString(id) && id != config.SystemAIUserID }

// Detail loads the user page. Phone numbers are masked unless role is owner;
// neither OTP codes nor any other secret is ever read.
func (s *AdminUserService) Detail(ctx context.Context, role, id string) (*AdminUserDetail, error) {
	if !validUserID(id) {
		return nil, ErrUserNotFound
	}
	d, err := s.store.GetUserDetail(ctx, id)
	if errors.Is(err, repository.ErrAdminUserNotFound) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.Detail: %w", err)
	}
	referred, err := s.store.UserReferred(ctx, id, adminDetailListLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.Detail: %w", err)
	}
	rewards, err := s.store.UserRewards(ctx, id, adminDetailListLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.Detail: %w", err)
	}
	matches, err := s.store.UserMatches(ctx, id, adminDetailMatchLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.Detail: %w", err)
	}
	daily, err := s.store.UserDailyAttempts(ctx, id, adminDetailDailyLimit)
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.Detail: %w", err)
	}

	level := config.LevelFromXP(d.XP)
	out := &AdminUserDetail{
		AdminUserItem: s.item(d.AdminUserRow, role),
		ReferralCode:  d.ReferralCode, BanReason: d.BanReason, JoinedAt: d.PhoneVerifiedAt,
		XPInLevel: d.XP - config.XPForLevel(level), XPForNext: config.XPForLevel(level+1) - config.XPForLevel(level),
		Stats: userStatsView{
			TotalMatches: d.Stats.TotalMatches, Wins: d.Stats.Wins, LongestWord: d.Stats.LongestWord,
			BestMatchStreak: d.Stats.BestMatchStreak, DailyStreak: d.Stats.DailyStreak,
			LongestDailyStreak: d.Stats.LongestDailyStreak, LastPlayedDate: d.Stats.LastPlayedDate,
			TotalScore: d.Stats.TotalScore,
		},
		FriendsCount: d.FriendsCount, DeviceTokens: d.DeviceTokens, ReferredCount: d.ReferredCount,
		Referred: make([]referredView, len(referred)), Rewards: make([]rewardView, len(rewards)),
		Matches: make([]matchView, len(matches)), DailyAttempts: make([]dailyView, len(daily)),
	}
	if d.ReferrerID != "" {
		out.Referrer = &userRef{ID: d.ReferrerID, Username: d.ReferrerUsername}
	}
	for i, r := range referred {
		out.Referred[i] = referredView{ID: r.ID, Username: r.Username, CreatedAt: r.CreatedAt}
	}
	for i, r := range rewards {
		out.Rewards[i] = rewardView{ID: r.ID, Kind: r.Kind, Detail: r.Detail, Coins: r.Coins,
			Claimed: r.ClaimedAt != nil, ClaimedAt: r.ClaimedAt, CreatedAt: r.CreatedAt}
	}
	for i, m := range matches {
		out.Matches[i] = matchView{ID: m.ID, Mode: m.Mode, Status: m.Status, Kind: m.Kind, Score: m.Score,
			Won: m.Won, At: m.At, EndedAt: m.EndedAt, PlayerCount: m.PlayerCount}
	}
	for i, a := range daily {
		out.DailyAttempts[i] = dailyView{Date: a.Date.Format("2006-01-02"), Attempt: a.Attempt, Score: a.Score,
			ChainLength: a.ChainLength, CompletedAt: a.CompletedAt}
	}
	return out, nil
}

// cleanReason validates the mandatory free-text justification of an action.
func cleanReason(reason string) (string, error) {
	reason = strings.TrimSpace(reason)
	n := utf8.RuneCountInString(reason)
	if n < AdminReasonMinRunes || n > AdminReasonMaxRunes {
		return "", ErrReasonRequired
	}
	return reason, nil
}

func userTarget(id string) AuditTarget { return AuditTarget{Type: "user", ID: id} }

// CoinsResult is what a coin action reports back.
type CoinsResult struct {
	Mode    string `json:"mode"`
	Amount  int    `json:"amount"`
	Balance *int   `json:"balance,omitempty"` // direct mode only
}

// AdjustCoins changes a user's coins. mode "direct" applies amount (±) to the
// balance immediately; mode "reward" creates a claimable inbox reward
// (kind admin_gift, amount must be positive) that the player collects in the app.
func (s *AdminUserService) AdjustCoins(ctx context.Context, actor AuditActor, id, mode string, amount int, reason string) (*CoinsResult, error) {
	if !validUserID(id) {
		return nil, ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return nil, err
	}
	if amount == 0 || amount > AdminMaxCoinAdjust || amount < -AdminMaxCoinAdjust {
		return nil, ErrInvalidAmount
	}

	switch mode {
	case CoinModeDirect:
		balance, err := s.store.AdjustCoins(ctx, id, amount)
		if errors.Is(err, repository.ErrAdminUserNotFound) {
			return nil, ErrUserNotFound
		}
		if err != nil {
			return nil, fmt.Errorf("AdminUserService.AdjustCoins: %w", err)
		}
		s.audit.LogRecord(ctx, actor, "user.coins", userTarget(id), map[string]any{
			"mode": mode, "amount": amount, "balance_before": balance - amount, "balance_after": balance, "reason": reason,
		})
		return &CoinsResult{Mode: mode, Amount: amount, Balance: &balance}, nil

	case CoinModeReward:
		if amount < 0 {
			return nil, ErrInvalidAmount
		}
		if _, err := s.store.GetUserDetail(ctx, id); errors.Is(err, repository.ErrAdminUserNotFound) {
			return nil, ErrUserNotFound
		} else if err != nil {
			return nil, fmt.Errorf("AdminUserService.AdjustCoins: %w", err)
		}
		ref, err := randomRef()
		if err != nil {
			return nil, fmt.Errorf("AdminUserService.AdjustCoins: %w", err)
		}
		if _, err := s.rewards.CreateInboxReward(ctx, id, repository.RewardAdminGift, ref, "", amount); err != nil {
			return nil, fmt.Errorf("AdminUserService.AdjustCoins: %w", err)
		}
		s.audit.LogRecord(ctx, actor, "user.coins", userTarget(id), map[string]any{
			"mode": mode, "amount": amount, "reward_ref": ref, "reason": reason,
		})
		return &CoinsResult{Mode: mode, Amount: amount}, nil
	}
	return nil, ErrInvalidAmount
}

func randomRef() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("random ref: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// PremiumResult reports the user's premium state after an action.
type PremiumResult struct {
	Premium      bool       `json:"premium"`
	PremiumUntil *time.Time `json:"premium_until"`
}

// GrantPremium adds days on top of any remaining premium time.
func (s *AdminUserService) GrantPremium(ctx context.Context, actor AuditActor, id string, days int, reason string) (*PremiumResult, error) {
	if !validUserID(id) {
		return nil, ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return nil, err
	}
	if days < 1 || days > AdminMaxPremiumDays {
		return nil, ErrInvalidDays
	}
	until, err := s.store.ExtendPremium(ctx, id, days)
	if errors.Is(err, repository.ErrAdminUserNotFound) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminUserService.GrantPremium: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "user.premium_grant", userTarget(id), map[string]any{
		"days": days, "premium_until": until, "reason": reason,
	})
	return &PremiumResult{Premium: until.After(s.now()), PremiumUntil: &until}, nil
}

// RevokePremium ends the user's premium immediately.
func (s *AdminUserService) RevokePremium(ctx context.Context, actor AuditActor, id, reason string) (*PremiumResult, error) {
	if !validUserID(id) {
		return nil, ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return nil, err
	}
	if err := s.store.RevokePremium(ctx, id); errors.Is(err, repository.ErrAdminUserNotFound) {
		return nil, ErrUserNotFound
	} else if err != nil {
		return nil, fmt.Errorf("AdminUserService.RevokePremium: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "user.premium_revoke", userTarget(id), map[string]any{"reason": reason})
	return &PremiumResult{}, nil
}

// Rename changes the username with the same validation as the in-app rename.
func (s *AdminUserService) Rename(ctx context.Context, actor AuditActor, id, username, reason string) (string, error) {
	if !validUserID(id) {
		return "", ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return "", err
	}
	before, err := s.store.GetUserDetail(ctx, id)
	if errors.Is(err, repository.ErrAdminUserNotFound) {
		return "", ErrUserNotFound
	}
	if err != nil {
		return "", fmt.Errorf("AdminUserService.Rename: %w", err)
	}
	after, err := s.renamer.UpdateUsername(ctx, id, username)
	if err != nil {
		return "", err // ErrInvalidUsername / ErrUsernameTaken pass through to the handler
	}
	s.audit.LogRecord(ctx, actor, "user.rename", userTarget(id), map[string]any{
		"from": before.Username, "to": after, "reason": reason,
	})
	return after, nil
}

// ClearAvatar removes the user's chosen avatar.
func (s *AdminUserService) ClearAvatar(ctx context.Context, actor AuditActor, id, reason string) error {
	if !validUserID(id) {
		return ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return err
	}
	previous, err := s.store.ClearAvatar(ctx, id)
	if errors.Is(err, repository.ErrAdminUserNotFound) {
		return ErrUserNotFound
	}
	if err != nil {
		return fmt.Errorf("AdminUserService.ClearAvatar: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "user.avatar_clear", userTarget(id), map[string]any{
		"previous_avatar": previous, "reason": reason,
	})
	return nil
}

// Ban suspends the account: it can no longer sign in, refresh, call the API,
// join the WebSocket or the queue, and drops off the leaderboards.
func (s *AdminUserService) Ban(ctx context.Context, actor AuditActor, id, reason string) error {
	if !validUserID(id) {
		return ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return err
	}
	if err := s.store.BanUser(ctx, id, reason); errors.Is(err, repository.ErrAdminUserNotFound) {
		return ErrUserNotFound
	} else if err != nil {
		return fmt.Errorf("AdminUserService.Ban: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "user.ban", userTarget(id), map[string]any{"reason": reason})
	return nil
}

// Unban lifts a ban.
func (s *AdminUserService) Unban(ctx context.Context, actor AuditActor, id, reason string) error {
	if !validUserID(id) {
		return ErrUserNotFound
	}
	reason, err := cleanReason(reason)
	if err != nil {
		return err
	}
	if err := s.store.UnbanUser(ctx, id); errors.Is(err, repository.ErrAdminUserNotFound) {
		return ErrUserNotFound
	} else if err != nil {
		return fmt.Errorf("AdminUserService.Unban: %w", err)
	}
	s.audit.LogRecord(ctx, actor, "user.unban", userTarget(id), map[string]any{"reason": reason})
	return nil
}
