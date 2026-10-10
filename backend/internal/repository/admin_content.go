package repository

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/lib/pq"
)

// ErrDailyLocked is returned when a start-letter change hits a day that is no
// longer in the future.
var ErrDailyLocked = errors.New("daily challenge day is not in the future")

// AdminTaunt is a taunt as the catalogue page lists it.
type AdminTaunt struct {
	ID        string
	Text      string
	SortOrder int
	CreatedAt time.Time
}

// ListTauntsAdmin reads the taunts straight from the table (no 30 s cache), in picker order.
func (r *AdminRepository) ListTauntsAdmin(ctx context.Context) ([]AdminTaunt, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, text, sort_order, created_at FROM taunts ORDER BY sort_order, created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.ListTauntsAdmin: %w", err)
	}
	defer rows.Close()
	out := []AdminTaunt{}
	for rows.Next() {
		var t AdminTaunt
		if err := rows.Scan(&t.ID, &t.Text, &t.SortOrder, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.ListTauntsAdmin scan: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// AdminAvatar is an avatar as the catalogue page lists it, with how many users picked it.
type AdminAvatar struct {
	ID          string
	SortOrder   int
	ContentType string
	Bytes       int
	UpdatedAt   time.Time
	Users       int // users whose avatar_id is this avatar
	ActiveUsers int // …of which have an active premium subscription (so see it)
}

const avatarUsageJoin = `
LEFT JOIN (
    SELECT avatar_id, count(*) AS n, count(*) FILTER (WHERE premium_until > now()) AS active
    FROM users WHERE avatar_id IS NOT NULL GROUP BY avatar_id
) c ON c.avatar_id = a.id`

// ListAvatarsAdmin reads the avatars (without image bytes), in picker order.
func (r *AdminRepository) ListAvatarsAdmin(ctx context.Context) ([]AdminAvatar, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT a.id, a.sort_order, a.content_type, octet_length(a.image), a.updated_at,
       COALESCE(c.n, 0), COALESCE(c.active, 0)
FROM avatars a`+avatarUsageJoin+`
ORDER BY a.sort_order, a.created_at, a.id`)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.ListAvatarsAdmin: %w", err)
	}
	defer rows.Close()
	out := []AdminAvatar{}
	for rows.Next() {
		var a AdminAvatar
		if err := rows.Scan(&a.ID, &a.SortOrder, &a.ContentType, &a.Bytes, &a.UpdatedAt, &a.Users, &a.ActiveUsers); err != nil {
			return nil, fmt.Errorf("AdminRepository.ListAvatarsAdmin scan: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// AvatarUsage counts the users who picked the avatar, or ErrCatalogItemNotFound.
func (r *AdminRepository) AvatarUsage(ctx context.Context, id string) (users, active int, err error) {
	err = r.db.QueryRowContext(ctx, `
SELECT COALESCE(c.n, 0), COALESCE(c.active, 0)
FROM avatars a`+avatarUsageJoin+`
WHERE a.id = $1`, id).Scan(&users, &active)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, 0, ErrCatalogItemNotFound
	}
	if err != nil {
		return 0, 0, fmt.Errorf("AdminRepository.AvatarUsage: %w", err)
	}
	return users, active, nil
}

// AdminDailyRow is one daily_challenges row with its attempt totals.
type AdminDailyRow struct {
	Date        time.Time
	Seed        int64
	StartLetter string
	Players     int
	Attempts    int
	BestScore   int
}

// ListDaily returns the existing challenge rows with from <= date <= to, newest first.
func (r *AdminRepository) ListDaily(ctx context.Context, from, to time.Time) ([]AdminDailyRow, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT c.challenge_date, c.seed, c.start_letter,
       COALESCE(a.players, 0), COALESCE(a.attempts, 0), COALESCE(a.best, 0)
FROM daily_challenges c
LEFT JOIN (
    SELECT challenge_date, count(DISTINCT user_id) AS players, count(*) AS attempts, max(score) AS best
    FROM daily_challenge_attempts WHERE challenge_date BETWEEN $1 AND $2 GROUP BY challenge_date
) a ON a.challenge_date = c.challenge_date
WHERE c.challenge_date BETWEEN $1 AND $2
ORDER BY c.challenge_date DESC`, from, to)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.ListDaily: %w", err)
	}
	defer rows.Close()
	out := []AdminDailyRow{}
	for rows.Next() {
		var d AdminDailyRow
		if err := rows.Scan(&d.Date, &d.Seed, &d.StartLetter, &d.Players, &d.Attempts, &d.BestScore); err != nil {
			return nil, fmt.Errorf("AdminRepository.ListDaily scan: %w", err)
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// AdminDailyStats are the totals of one challenge day.
type AdminDailyStats struct {
	Players   int
	Attempts  int
	Retries   int // paid second attempts bought (daily_retries)
	BestScore int
	AvgScore  float64
}

func (r *AdminRepository) DailyStats(ctx context.Context, date time.Time) (AdminDailyStats, error) {
	var s AdminDailyStats
	err := r.db.QueryRowContext(ctx, `
SELECT count(DISTINCT user_id), count(*), COALESCE(max(score), 0), COALESCE(avg(score), 0)
FROM daily_challenge_attempts WHERE challenge_date = $1`, date).Scan(&s.Players, &s.Attempts, &s.BestScore, &s.AvgScore)
	if err != nil {
		return s, fmt.Errorf("AdminRepository.DailyStats: %w", err)
	}
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM daily_retries WHERE challenge_date = $1`, date).Scan(&s.Retries); err != nil {
		return s, fmt.Errorf("AdminRepository.DailyStats retries: %w", err)
	}
	return s, nil
}

// AdminDayAttempt is one stored attempt of a challenge day.
type AdminDayAttempt struct {
	UserID      string
	Username    string
	Attempt     int
	Score       int
	ChainLength int
	WordChain   []string
	CompletedAt time.Time
}

// DailyAttempts returns the newest attempts of the day, with their word chains.
func (r *AdminRepository) DailyAttempts(ctx context.Context, date time.Time, limit int) ([]AdminDayAttempt, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT a.user_id, COALESCE(u.username, ''), a.attempt_number, a.score, a.chain_length, a.word_chain, a.completed_at
FROM daily_challenge_attempts a JOIN users u ON u.id = a.user_id
WHERE a.challenge_date = $1
ORDER BY a.completed_at DESC LIMIT $2`, date, limit)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.DailyAttempts: %w", err)
	}
	defer rows.Close()
	out := []AdminDayAttempt{}
	for rows.Next() {
		var a AdminDayAttempt
		var wc pq.StringArray
		if err := rows.Scan(&a.UserID, &a.Username, &a.Attempt, &a.Score, &a.ChainLength, &wc, &a.CompletedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.DailyAttempts scan: %w", err)
		}
		a.WordChain = []string(wc)
		if a.WordChain == nil {
			a.WordChain = []string{}
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// AdminDailyRewards counts the payout inbox rewards that exist for a day.
type AdminDailyRewards struct {
	DoneCreated, DoneClaimed int
	RankCreated, RankClaimed int
	CoinsCreated             int
}

func (r *AdminRepository) DailyRewards(ctx context.Context, date time.Time) (AdminDailyRewards, error) {
	var out AdminDailyRewards
	rows, err := r.db.QueryContext(ctx, `
SELECT kind, count(*), count(claimed_at), COALESCE(sum(coins), 0)
FROM inbox_rewards
WHERE kind IN ('daily_done', 'daily_rank') AND ref = $1
GROUP BY kind`, date.Format("2006-01-02"))
	if err != nil {
		return out, fmt.Errorf("AdminRepository.DailyRewards: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var kind string
		var created, claimed, coins int
		if err := rows.Scan(&kind, &created, &claimed, &coins); err != nil {
			return out, fmt.Errorf("AdminRepository.DailyRewards scan: %w", err)
		}
		out.CoinsCreated += coins
		if kind == RewardDailyDone {
			out.DoneCreated, out.DoneClaimed = created, claimed
		} else {
			out.RankCreated, out.RankClaimed = created, claimed
		}
	}
	return out, rows.Err()
}

// SetDailyStartLetter inserts the challenge row for a future day or changes
// its start letter, only while the day is after today (the guard is in SQL so a
// midnight rollover between the service check and the write cannot slip a
// change into a live day). It returns ErrDailyLocked when the day is not
// after today.
func (r *AdminRepository) SetDailyStartLetter(ctx context.Context, date time.Time, seed int64, letter string, today time.Time) error {
	res, err := r.db.ExecContext(ctx, `
INSERT INTO daily_challenges (challenge_date, seed, start_letter)
SELECT $1::date, $2::bigint, $3::varchar WHERE $1::date > $4::date
ON CONFLICT (challenge_date) DO UPDATE SET start_letter = EXCLUDED.start_letter
WHERE daily_challenges.challenge_date > $4::date`, date, seed, letter, today)
	if err != nil {
		return fmt.Errorf("AdminRepository.SetDailyStartLetter: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrDailyLocked
	}
	return nil
}

// AdminWeeklyReward is one paid weekly-leaderboard prize.
type AdminWeeklyReward struct {
	WeekStart time.Time
	Rank      int
	UserID    string
	Username  string
	Coins     int
	AwardedAt time.Time
	Banned    bool
}

// WeeklyRewards returns the prizes of the latest `weeks` payout dates, newest first.
func (r *AdminRepository) WeeklyRewards(ctx context.Context, weeks int) ([]AdminWeeklyReward, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT w.week_start, w.rank, w.user_id, COALESCE(u.username, ''), w.coins_awarded, w.awarded_at, u.banned_at IS NOT NULL
FROM weekly_leaderboard_rewards w JOIN users u ON u.id = w.user_id
WHERE w.week_start IN (SELECT DISTINCT week_start FROM weekly_leaderboard_rewards ORDER BY week_start DESC LIMIT $1)
ORDER BY w.week_start DESC, w.rank, w.awarded_at`, weeks)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.WeeklyRewards: %w", err)
	}
	defer rows.Close()
	out := []AdminWeeklyReward{}
	for rows.Next() {
		var w AdminWeeklyReward
		if err := rows.Scan(&w.WeekStart, &w.Rank, &w.UserID, &w.Username, &w.Coins, &w.AwardedAt, &w.Banned); err != nil {
			return nil, fmt.Errorf("AdminRepository.WeeklyRewards scan: %w", err)
		}
		out = append(out, w)
	}
	return out, rows.Err()
}
