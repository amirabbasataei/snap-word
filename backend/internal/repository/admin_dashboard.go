package repository

import (
	"context"
	"fmt"
	"time"

	"wordchain/backend/internal/config"
)

// DashboardCounts is the database half of the admin dashboard summary.
type DashboardCounts struct {
	UsersTotal             int
	UsersNewToday          int
	UsersNew7d             int
	PremiumActive          int
	CoinsInCirculation     int64
	MatchesTodaySolo       int // classic, one human, uploaded from the device (solo or vs on-device AI)
	MatchesTodayVersus     int // classic, two humans
	MatchesTodayAIOnline   int // classic, matchmaking fell back to the server AI
	MatchesTodayDaily      int
	DailyParticipantsToday int
	UnclaimedRewards       int
	UnclaimedRewardCoins   int64
}

// DashboardDay is one Iran-time calendar day of the dashboard time series.
type DashboardDay struct {
	Day           time.Time // midnight UTC of the Iran date
	Signups       int
	MatchesSolo   int
	MatchesVersus int
	MatchesAI     int
	MatchesDaily  int
	DailyAttempts int
	CoinsClaimed  int64
}

// iranDay converts a timestamptz column to its Iran (UTC+03:30) calendar date.
const iranDay = `((%s AT TIME ZONE 'UTC') + interval '3 hours 30 minutes')::date`

// matchKind classifies a match from its mode and players. Uploaded solo/AI
// games carry a single match_players row (the server cannot tell solo from an
// on-device AI game), matchmaking games carry two.
const matchKindCTE = `
match_kind AS (
  SELECT m.id,
         COALESCE(m.started_at, m.created_at) AS at,
         CASE
           WHEN m.mode = 'daily' THEN 'daily'
           WHEN p.n >= 2 AND p.has_ai THEN 'ai'
           WHEN p.n >= 2 THEN 'versus'
           ELSE 'solo'
         END AS kind
  FROM matches m
  LEFT JOIN LATERAL (
    SELECT count(*) AS n, COALESCE(bool_or(is_ai), false) AS has_ai
    FROM match_players WHERE match_id = m.id
  ) p ON true
  WHERE m.status <> 'pending'
)`

// DashboardCounts reads every database-backed headline number at once.
func (r *AdminRepository) DashboardCounts(ctx context.Context, now time.Time) (*DashboardCounts, error) {
	l := now.In(config.IranLocation)
	todayStart := time.Date(l.Year(), l.Month(), l.Day(), 0, 0, 0, 0, config.IranLocation)
	weekStart := todayStart.AddDate(0, 0, -6)
	today := config.IranDate(now)

	q := `WITH ` + matchKindCTE + `
SELECT
  (SELECT count(*) FROM users WHERE phone_verified_at IS NOT NULL AND id <> $4),
  (SELECT count(*) FROM users WHERE phone_verified_at >= $1 AND id <> $4),
  (SELECT count(*) FROM users WHERE phone_verified_at >= $2 AND id <> $4),
  (SELECT count(*) FROM users WHERE premium_until > $3),
  (SELECT COALESCE(SUM(coins), 0) FROM users WHERE id <> $4),
  (SELECT count(*) FROM match_kind WHERE at >= $1 AND kind = 'solo'),
  (SELECT count(*) FROM match_kind WHERE at >= $1 AND kind = 'versus'),
  (SELECT count(*) FROM match_kind WHERE at >= $1 AND kind = 'ai'),
  (SELECT count(*) FROM match_kind WHERE at >= $1 AND kind = 'daily'),
  (SELECT count(DISTINCT user_id) FROM daily_challenge_attempts WHERE challenge_date = $5),
  (SELECT count(*) FROM inbox_rewards WHERE claimed_at IS NULL),
  (SELECT COALESCE(SUM(coins), 0) FROM inbox_rewards WHERE claimed_at IS NULL)`

	var c DashboardCounts
	err := r.db.QueryRowContext(ctx, q, todayStart, weekStart, now, config.SystemAIUserID, today).Scan(
		&c.UsersTotal, &c.UsersNewToday, &c.UsersNew7d, &c.PremiumActive, &c.CoinsInCirculation,
		&c.MatchesTodaySolo, &c.MatchesTodayVersus, &c.MatchesTodayAIOnline, &c.MatchesTodayDaily,
		&c.DailyParticipantsToday, &c.UnclaimedRewards, &c.UnclaimedRewardCoins,
	)
	if err != nil {
		return nil, fmt.Errorf("DashboardCounts: %w", err)
	}
	return &c, nil
}

// DashboardTimeseries returns one row per Iran day from..to inclusive (dates
// as midnight UTC, see config.IranDate); days without activity are zero rows.
func (r *AdminRepository) DashboardTimeseries(ctx context.Context, from, to time.Time) ([]DashboardDay, error) {
	q := `WITH days AS (
  SELECT d::date AS day FROM generate_series($1::date, $2::date, interval '1 day') d
),
` + matchKindCTE + `,
signups AS (
  SELECT ` + fmt.Sprintf(iranDay, "phone_verified_at") + ` AS day, count(*) AS n
  FROM users WHERE phone_verified_at IS NOT NULL AND id <> $3 GROUP BY 1
),
matches_by_day AS (
  SELECT ` + fmt.Sprintf(iranDay, "at") + ` AS day,
         count(*) FILTER (WHERE kind = 'solo')   AS solo,
         count(*) FILTER (WHERE kind = 'versus') AS versus,
         count(*) FILTER (WHERE kind = 'ai')     AS ai,
         count(*) FILTER (WHERE kind = 'daily')  AS daily
  FROM match_kind GROUP BY 1
),
attempts AS (
  SELECT challenge_date AS day, count(*) AS n FROM daily_challenge_attempts GROUP BY 1
),
claimed AS (
  SELECT ` + fmt.Sprintf(iranDay, "claimed_at") + ` AS day, SUM(coins) AS coins
  FROM inbox_rewards WHERE claimed_at IS NOT NULL GROUP BY 1
)
SELECT days.day,
       COALESCE(s.n, 0), COALESCE(m.solo, 0), COALESCE(m.versus, 0), COALESCE(m.ai, 0), COALESCE(m.daily, 0),
       COALESCE(a.n, 0), COALESCE(c.coins, 0)
FROM days
LEFT JOIN signups s ON s.day = days.day
LEFT JOIN matches_by_day m ON m.day = days.day
LEFT JOIN attempts a ON a.day = days.day
LEFT JOIN claimed c ON c.day = days.day
ORDER BY days.day`

	rows, err := r.db.QueryContext(ctx, q, from, to, config.SystemAIUserID)
	if err != nil {
		return nil, fmt.Errorf("DashboardTimeseries: %w", err)
	}
	defer rows.Close()

	var out []DashboardDay
	for rows.Next() {
		var d DashboardDay
		if err := rows.Scan(&d.Day, &d.Signups, &d.MatchesSolo, &d.MatchesVersus, &d.MatchesAI,
			&d.MatchesDaily, &d.DailyAttempts, &d.CoinsClaimed); err != nil {
			return nil, fmt.Errorf("DashboardTimeseries scan: %w", err)
		}
		out = append(out, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("DashboardTimeseries rows: %w", err)
	}
	return out, nil
}
