package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrAdminUserNotFound = errors.New("user not found")
	ErrAlreadyBanned     = errors.New("user already banned")
	ErrNotBanned         = errors.New("user not banned")
)

// AdminUserFilter values accepted by ListUsers.
const (
	AdminFilterPremium = "premium"
	AdminFilterBanned  = "banned"
	AdminFilterNew     = "new"
)

// AdminUserListParams selects one page of the users table. SortColumn must be
// one of the keys of adminUserSorts; the service validates it.
type AdminUserListParams struct {
	Query       string // free text: username fragment, referral code or user id
	PhoneDigits string // digits to match inside the phone; empty = phone not searched
	Filter      string // "", premium, banned or new
	SortColumn  string
	Desc        bool
	Page        int // 1-based
	PageSize    int
	ExcludeID   string // the seeded AI user
	NewSince    time.Time
}

// adminUserSorts maps the public sort keys to SQL (never built from user input).
var adminUserSorts = map[string]string{
	"created":  "u.created_at",
	"coins":    "u.coins",
	"xp":       "COALESCE(ps.xp, 0)",
	"matches":  "COALESCE(ps.total_matches, 0)",
	"username": "LOWER(u.username)",
}

// AdminUserSortable reports whether key is a valid sort key.
func AdminUserSortable(key string) bool {
	_, ok := adminUserSorts[key]
	return ok
}

// AdminUserRow is one line of the users table. Phone is the raw number; the
// service masks it before it leaves the process.
type AdminUserRow struct {
	ID           string
	Username     string
	Phone        string
	Coins        int
	XP           int64
	TotalMatches int
	PremiumUntil *time.Time
	AvatarID     string
	CreatedAt    time.Time
	BannedAt     *time.Time
}

const adminUserSelect = `
SELECT u.id, COALESCE(u.username, ''), u.phone, u.coins, COALESCE(ps.xp, 0), COALESCE(ps.total_matches, 0),
       u.premium_until, COALESCE(u.avatar_id, ''), u.created_at, u.banned_at
FROM users u
LEFT JOIN player_stats ps ON ps.user_id = u.id`

// escapeLike makes s safe inside a LIKE pattern.
func escapeLike(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
}

// ListUsers returns one page of registered users plus the total matching count.
func (r *AdminRepository) ListUsers(ctx context.Context, p AdminUserListParams) ([]AdminUserRow, int, error) {
	where := []string{`u.phone_verified_at IS NOT NULL`, `u.id <> $1`}
	args := []any{p.ExcludeID}
	arg := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}

	if p.Query != "" {
		ors := []string{
			`u.username ILIKE ` + arg("%"+escapeLike(p.Query)+"%"),
			`u.referral_code = ` + arg(strings.ToUpper(p.Query)),
			`u.id::text = ` + arg(strings.ToLower(p.Query)),
		}
		if p.PhoneDigits != "" {
			ors = append(ors, `u.phone LIKE `+arg("%"+escapeLike(p.PhoneDigits)+"%"))
		}
		where = append(where, "("+strings.Join(ors, " OR ")+")")
	}
	switch p.Filter {
	case AdminFilterPremium:
		where = append(where, `u.premium_until > now()`)
	case AdminFilterBanned:
		where = append(where, `u.banned_at IS NOT NULL`)
	case AdminFilterNew:
		where = append(where, `u.phone_verified_at >= `+arg(p.NewSince))
	}
	whereSQL := ` WHERE ` + strings.Join(where, " AND ")

	var total int
	countSQL := `SELECT count(*) FROM users u` + whereSQL
	if err := r.db.QueryRowContext(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListUsers count: %w", err)
	}

	col, ok := adminUserSorts[p.SortColumn]
	if !ok {
		col = adminUserSorts["created"]
	}
	dir := "ASC"
	if p.Desc {
		dir = "DESC"
	}
	limit, offset := arg(p.PageSize), arg((p.Page-1)*p.PageSize)
	q := adminUserSelect + whereSQL + fmt.Sprintf(` ORDER BY %s %s, u.id LIMIT %s OFFSET %s`, col, dir, limit, offset)

	rows, err := r.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListUsers: %w", err)
	}
	defer rows.Close()

	out := []AdminUserRow{}
	for rows.Next() {
		row, err := scanAdminUserRow(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("AdminRepository.ListUsers scan: %w", err)
		}
		out = append(out, *row)
	}
	return out, total, rows.Err()
}

func scanAdminUserRow(row interface{ Scan(...any) error }) (*AdminUserRow, error) {
	var (
		u               AdminUserRow
		premium, banned sql.NullTime
	)
	if err := row.Scan(&u.ID, &u.Username, &u.Phone, &u.Coins, &u.XP, &u.TotalMatches,
		&premium, &u.AvatarID, &u.CreatedAt, &banned); err != nil {
		return nil, err
	}
	if premium.Valid {
		u.PremiumUntil = &premium.Time
	}
	if banned.Valid {
		u.BannedAt = &banned.Time
	}
	return &u, nil
}

// AdminUserDetail is the profile block of the user page.
type AdminUserDetail struct {
	AdminUserRow
	ReferralCode     string
	BanReason        string
	PhoneVerifiedAt  *time.Time
	ReferrerID       string
	ReferrerUsername string
	Stats            AdminUserStats
	FriendsCount     int
	DeviceTokens     int
	ReferredCount    int
}

// AdminUserStats mirrors player_stats (zero values when the player never finished a game).
type AdminUserStats struct {
	TotalMatches       int
	Wins               int
	LongestWord        string
	BestMatchStreak    int
	DailyStreak        int
	LongestDailyStreak int
	LastPlayedDate     *time.Time
	TotalScore         int64
	XP                 int64
}

// AdminReferred is one account that signed up (or redeemed) with this user's code.
type AdminReferred struct {
	ID        string
	Username  string
	CreatedAt time.Time
}

// AdminReward is one inbox_rewards row.
type AdminReward struct {
	ID        string
	Kind      string
	Detail    string
	Coins     int
	ClaimedAt *time.Time
	CreatedAt time.Time
}

// AdminUserMatch is one match the user took part in.
type AdminUserMatch struct {
	ID          string
	Mode        string
	Status      string
	Kind        string // solo | versus | ai | daily (derived, see matchKindCTE)
	Score       int
	Won         bool
	At          time.Time
	EndedAt     *time.Time
	PlayerCount int
}

// AdminDailyAttempt is one Daily Challenge attempt.
type AdminDailyAttempt struct {
	Date        time.Time
	Attempt     int
	Score       int
	ChainLength int
	CompletedAt time.Time
}

// GetUserDetail loads the profile block, or ErrAdminUserNotFound.
func (r *AdminRepository) GetUserDetail(ctx context.Context, id string) (*AdminUserDetail, error) {
	const q = `
SELECT u.id, COALESCE(u.username, ''), u.phone, u.coins, COALESCE(ps.xp, 0), COALESCE(ps.total_matches, 0),
       u.premium_until, COALESCE(u.avatar_id, ''), u.created_at, u.banned_at,
       COALESCE(u.referral_code, ''), COALESCE(u.ban_reason, ''), u.phone_verified_at,
       COALESCE(u.referred_by::text, ''), COALESCE(ref.username, ''),
       COALESCE(ps.wins, 0), COALESCE(ps.longest_word, ''), COALESCE(ps.best_match_streak, 0),
       COALESCE(ps.daily_streak, 0), COALESCE(ps.longest_daily_streak, 0), ps.last_played_date,
       COALESCE(ps.total_score, 0),
       (SELECT count(*) FROM friendships f
         WHERE f.status = 'accepted' AND (f.requester_id = u.id OR f.addressee_id = u.id)),
       (SELECT count(*) FROM device_tokens d WHERE d.user_id = u.id),
       (SELECT count(*) FROM users r WHERE r.referred_by = u.id)
FROM users u
LEFT JOIN player_stats ps ON ps.user_id = u.id
LEFT JOIN users ref ON ref.id = u.referred_by
WHERE u.id = $1 AND u.phone_verified_at IS NOT NULL`

	var (
		d                         AdminUserDetail
		premium, banned, verified sql.NullTime
		lastPlayed                sql.NullTime
	)
	err := r.db.QueryRowContext(ctx, q, id).Scan(
		&d.ID, &d.Username, &d.Phone, &d.Coins, &d.XP, &d.TotalMatches,
		&premium, &d.AvatarID, &d.CreatedAt, &banned,
		&d.ReferralCode, &d.BanReason, &verified,
		&d.ReferrerID, &d.ReferrerUsername,
		&d.Stats.Wins, &d.Stats.LongestWord, &d.Stats.BestMatchStreak,
		&d.Stats.DailyStreak, &d.Stats.LongestDailyStreak, &lastPlayed,
		&d.Stats.TotalScore,
		&d.FriendsCount, &d.DeviceTokens, &d.ReferredCount,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrAdminUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.GetUserDetail: %w", err)
	}
	if premium.Valid {
		d.PremiumUntil = &premium.Time
	}
	if banned.Valid {
		d.BannedAt = &banned.Time
	}
	if verified.Valid {
		d.PhoneVerifiedAt = &verified.Time
	}
	if lastPlayed.Valid {
		d.Stats.LastPlayedDate = &lastPlayed.Time
	}
	d.Stats.TotalMatches = d.TotalMatches
	d.Stats.XP = d.XP
	return &d, nil
}

// UserReferred lists the accounts linked to this user's referral code, newest first.
func (r *AdminRepository) UserReferred(ctx context.Context, id string, limit int) ([]AdminReferred, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT id, COALESCE(username, ''), created_at FROM users
		 WHERE referred_by = $1 ORDER BY created_at DESC LIMIT $2`, id, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.UserReferred: %w", err)
	}
	defer rows.Close()
	out := []AdminReferred{}
	for rows.Next() {
		var a AdminReferred
		if err := rows.Scan(&a.ID, &a.Username, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.UserReferred scan: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// UserRewards lists the user's inbox rewards (claimed and not), newest first.
func (r *AdminRepository) UserRewards(ctx context.Context, id string, limit int) ([]AdminReward, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT id, kind, detail, coins, claimed_at, created_at FROM inbox_rewards
		 WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`, id, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.UserRewards: %w", err)
	}
	defer rows.Close()
	out := []AdminReward{}
	for rows.Next() {
		var (
			a       AdminReward
			claimed sql.NullTime
		)
		if err := rows.Scan(&a.ID, &a.Kind, &a.Detail, &a.Coins, &claimed, &a.CreatedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.UserRewards scan: %w", err)
		}
		if claimed.Valid {
			a.ClaimedAt = &claimed.Time
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// UserMatches lists the user's most recent non-pending matches.
func (r *AdminRepository) UserMatches(ctx context.Context, id string, limit int) ([]AdminUserMatch, error) {
	const q = `
SELECT m.id, m.mode, m.status,
       CASE
         WHEN m.mode = 'daily' THEN 'daily'
         WHEN p.n >= 2 AND p.has_ai THEN 'ai'
         WHEN p.n >= 2 THEN 'versus'
         ELSE 'solo'
       END,
       mp.score, COALESCE(m.winner_id = $1, false),
       COALESCE(m.started_at, m.created_at), m.ended_at, p.n
FROM match_players mp
JOIN matches m ON m.id = mp.match_id
JOIN LATERAL (
  SELECT count(*) AS n, COALESCE(bool_or(is_ai), false) AS has_ai
  FROM match_players WHERE match_id = m.id
) p ON true
WHERE mp.user_id = $1 AND m.status <> 'pending'
ORDER BY COALESCE(m.started_at, m.created_at) DESC
LIMIT $2`
	rows, err := r.db.QueryContext(ctx, q, id, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.UserMatches: %w", err)
	}
	defer rows.Close()
	out := []AdminUserMatch{}
	for rows.Next() {
		var (
			a     AdminUserMatch
			ended sql.NullTime
		)
		if err := rows.Scan(&a.ID, &a.Mode, &a.Status, &a.Kind, &a.Score, &a.Won, &a.At, &ended, &a.PlayerCount); err != nil {
			return nil, fmt.Errorf("AdminRepository.UserMatches scan: %w", err)
		}
		if ended.Valid {
			a.EndedAt = &ended.Time
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// UserDailyAttempts lists the user's Daily Challenge attempts, newest day first.
func (r *AdminRepository) UserDailyAttempts(ctx context.Context, id string, limit int) ([]AdminDailyAttempt, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT challenge_date, attempt_number, score, chain_length, completed_at
		 FROM daily_challenge_attempts WHERE user_id = $1
		 ORDER BY challenge_date DESC, attempt_number DESC LIMIT $2`, id, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.UserDailyAttempts: %w", err)
	}
	defer rows.Close()
	out := []AdminDailyAttempt{}
	for rows.Next() {
		var a AdminDailyAttempt
		if err := rows.Scan(&a.Date, &a.Attempt, &a.Score, &a.ChainLength, &a.CompletedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.UserDailyAttempts scan: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// AdjustCoins adds delta (negative to take coins away) to the balance in one
// statement and returns the new balance. A deduction below zero changes
// nothing and returns ErrInsufficientCoins.
func (r *AdminRepository) AdjustCoins(ctx context.Context, id string, delta int) (int, error) {
	var balance int
	err := r.db.QueryRowContext(ctx,
		`UPDATE users SET coins = coins + $2 WHERE id = $1 AND coins + $2 >= 0 RETURNING coins`, id, delta).Scan(&balance)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, r.missingOrBroke(ctx, id)
	}
	if err != nil {
		return 0, fmt.Errorf("AdminRepository.AdjustCoins: %w", err)
	}
	return balance, nil
}

// missingOrBroke explains why a guarded UPDATE touched no row.
func (r *AdminRepository) missingOrBroke(ctx context.Context, id string) error {
	var exists bool
	if err := r.db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, id).Scan(&exists); err != nil {
		return fmt.Errorf("AdminRepository.missingOrBroke: %w", err)
	}
	if !exists {
		return ErrAdminUserNotFound
	}
	return ErrInsufficientCoins
}

// ExtendPremium adds days on top of any remaining premium time (never shortens
// it, same rule as scripts/grant_premium.sh) and returns the new expiry.
func (r *AdminRepository) ExtendPremium(ctx context.Context, id string, days int) (time.Time, error) {
	var until time.Time
	err := r.db.QueryRowContext(ctx,
		`UPDATE users
		 SET premium_until = GREATEST(COALESCE(premium_until, now()), now()) + make_interval(days => $2)
		 WHERE id = $1 RETURNING premium_until`, id, days).Scan(&until)
	if errors.Is(err, sql.ErrNoRows) {
		return time.Time{}, ErrAdminUserNotFound
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("AdminRepository.ExtendPremium: %w", err)
	}
	return until, nil
}

// RevokePremium ends premium immediately (premium_until = NULL).
func (r *AdminRepository) RevokePremium(ctx context.Context, id string) error {
	res, err := r.db.ExecContext(ctx, `UPDATE users SET premium_until = NULL WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("AdminRepository.RevokePremium: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrAdminUserNotFound
	}
	return nil
}

// ClearAvatar removes the chosen avatar and returns what it was ("" if none).
func (r *AdminRepository) ClearAvatar(ctx context.Context, id string) (string, error) {
	var previous string
	err := r.db.QueryRowContext(ctx,
		`UPDATE users u SET avatar_id = NULL
		 FROM (SELECT id, COALESCE(avatar_id, '') AS old FROM users WHERE id = $1 FOR UPDATE) o
		 WHERE u.id = o.id RETURNING o.old`, id).Scan(&previous)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrAdminUserNotFound
	}
	if err != nil {
		return "", fmt.Errorf("AdminRepository.ClearAvatar: %w", err)
	}
	return previous, nil
}

// BanUser marks the account banned. ErrAlreadyBanned if it already was.
func (r *AdminRepository) BanUser(ctx context.Context, id, reason string) error {
	res, err := r.db.ExecContext(ctx,
		`UPDATE users SET banned_at = now(), ban_reason = $2 WHERE id = $1 AND banned_at IS NULL`, id, reason)
	if err != nil {
		return fmt.Errorf("AdminRepository.BanUser: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return r.userStateConflict(ctx, id, ErrAlreadyBanned)
	}
	return nil
}

// UnbanUser lifts a ban. ErrNotBanned if the account was not banned.
func (r *AdminRepository) UnbanUser(ctx context.Context, id string) error {
	res, err := r.db.ExecContext(ctx,
		`UPDATE users SET banned_at = NULL, ban_reason = NULL WHERE id = $1 AND banned_at IS NOT NULL`, id)
	if err != nil {
		return fmt.Errorf("AdminRepository.UnbanUser: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return r.userStateConflict(ctx, id, ErrNotBanned)
	}
	return nil
}

func (r *AdminRepository) userStateConflict(ctx context.Context, id string, conflict error) error {
	var exists bool
	if err := r.db.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, id).Scan(&exists); err != nil {
		return fmt.Errorf("AdminRepository.userStateConflict: %w", err)
	}
	if !exists {
		return ErrAdminUserNotFound
	}
	return conflict
}
