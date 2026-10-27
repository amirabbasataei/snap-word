package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/lib/pq"
)

// AnalyticsDayPoint is one Iran-time day of the overview series.
type AnalyticsDayPoint struct {
	Day          time.Time
	Active       int // distinct installs with any event
	ActiveUsers  int // of those, installs signed in
	NewInstalls  int
	Sessions     int
	SessionMsSum int64
}

// AnalyticsOverviewData is the database half of the overview endpoint.
type AnalyticsOverviewData struct {
	Series        []AnalyticsDayPoint
	WAU, MAU      int
	TotalInstalls int
	LinkedInstall int // installs linked to an account
}

// AnalyticsOverview reads the DAU series for [from, to] plus WAU/MAU ending at
// `to`. Everything comes from the rollups and the installs table.
func (r *AdminRepository) AnalyticsOverview(ctx context.Context, from, to time.Time) (*AnalyticsOverviewData, error) {
	out := &AnalyticsOverviewData{}
	byDay := map[time.Time]*AnalyticsDayPoint{}
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		out.Series = append(out.Series, AnalyticsDayPoint{Day: d})
	}
	for i := range out.Series {
		byDay[out.Series[i].Day] = &out.Series[i]
	}

	rows, err := r.db.QueryContext(ctx,
		`SELECT day, count(*), count(user_id) FROM analytics_daily_active WHERE day BETWEEN $1 AND $2 GROUP BY day`, from, to)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsOverview active: %w", err)
	}
	for rows.Next() {
		var d time.Time
		var a, u int
		if err := rows.Scan(&d, &a, &u); err != nil {
			rows.Close()
			return nil, fmt.Errorf("AnalyticsOverview active scan: %w", err)
		}
		if p := byDay[d.UTC()]; p != nil {
			p.Active, p.ActiveUsers = a, u
		}
	}
	rows.Close()

	rows, err = r.db.QueryContext(ctx,
		`SELECT first_seen, count(*) FROM analytics_installs WHERE first_seen BETWEEN $1 AND $2 GROUP BY first_seen`, from, to)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsOverview installs: %w", err)
	}
	for rows.Next() {
		var d time.Time
		var n int
		if err := rows.Scan(&d, &n); err != nil {
			rows.Close()
			return nil, fmt.Errorf("AnalyticsOverview installs scan: %w", err)
		}
		if p := byDay[d.UTC()]; p != nil {
			p.NewInstalls = n
		}
	}
	rows.Close()

	rows, err = r.db.QueryContext(ctx,
		`SELECT day, sessions, total_ms FROM analytics_daily_sessions WHERE day BETWEEN $1 AND $2`, from, to)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsOverview sessions: %w", err)
	}
	for rows.Next() {
		var d time.Time
		var n int
		var ms int64
		if err := rows.Scan(&d, &n, &ms); err != nil {
			rows.Close()
			return nil, fmt.Errorf("AnalyticsOverview sessions scan: %w", err)
		}
		if p := byDay[d.UTC()]; p != nil {
			p.Sessions, p.SessionMsSum = n, ms
		}
	}
	rows.Close()

	err = r.db.QueryRowContext(ctx, `
SELECT
  (SELECT count(DISTINCT install_id) FROM analytics_daily_active WHERE day BETWEEN $1::date - 6 AND $1),
  (SELECT count(DISTINCT install_id) FROM analytics_daily_active WHERE day BETWEEN $1::date - 29 AND $1),
  (SELECT count(*) FROM analytics_installs),
  (SELECT count(*) FROM analytics_installs WHERE user_id IS NOT NULL)`, to).
		Scan(&out.WAU, &out.MAU, &out.TotalInstalls, &out.LinkedInstall)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsOverview totals: %w", err)
	}
	return out, nil
}

// RetentionCell is the number of a cohort's members active `Offset` days after
// the cohort day.
type RetentionCell struct {
	Cohort time.Time
	Offset int
	Count  int
}

// AnalyticsRetention returns cohort × day-offset counts (offset 0..30) for
// cohorts whose day is in [from, to]. by is "install" (cohort = first_seen) or
// "user" (cohort = the account's first active day).
func (r *AdminRepository) AnalyticsRetention(ctx context.Context, from, to time.Time, byUser bool) ([]RetentionCell, error) {
	q := `
SELECT c.first_seen, (a.day - c.first_seen), count(*)
FROM analytics_installs c
JOIN analytics_daily_active a ON a.install_id = c.install_id AND a.day BETWEEN c.first_seen AND c.first_seen + 30
WHERE c.first_seen BETWEEN $1 AND $2
GROUP BY 1, 2 ORDER BY 1, 2`
	if byUser {
		q = `
WITH ua AS (
  SELECT day, user_id FROM analytics_daily_active WHERE user_id IS NOT NULL GROUP BY day, user_id
), c AS (
  SELECT user_id, min(day) AS cohort FROM ua GROUP BY user_id
)
SELECT c.cohort, (ua.day - c.cohort), count(*)
FROM c JOIN ua ON ua.user_id = c.user_id AND ua.day BETWEEN c.cohort AND c.cohort + 30
WHERE c.cohort BETWEEN $1 AND $2
GROUP BY 1, 2 ORDER BY 1, 2`
	}
	rows, err := r.db.QueryContext(ctx, q, from, to)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsRetention: %w", err)
	}
	defer rows.Close()
	var out []RetentionCell
	for rows.Next() {
		var c RetentionCell
		if err := rows.Scan(&c.Cohort, &c.Offset, &c.Count); err != nil {
			return nil, fmt.Errorf("AnalyticsRetention scan: %w", err)
		}
		c.Cohort = c.Cohort.UTC()
		out = append(out, c)
	}
	return out, rows.Err()
}

// AnalyticsFunnel counts, for each step, the installs that reached it in order
// (each step's first occurrence at or after the previous step's) inside
// [from, to). It reads the raw events, so the caller bounds the window.
func (r *AdminRepository) AnalyticsFunnel(ctx context.Context, steps []string, from, to time.Time) ([]int, error) {
	n := len(steps)
	fromArg, toArg := n+1, n+2
	var ctes, sel []string
	for i := range steps {
		if i == 0 {
			ctes = append(ctes, fmt.Sprintf(
				`s1 AS (SELECT install_id, min(ts) AS t FROM analytics_events WHERE name = $1 AND ts >= $%d AND ts < $%d GROUP BY install_id)`,
				fromArg, toArg))
		} else {
			ctes = append(ctes, fmt.Sprintf(
				`s%[1]d AS (SELECT e.install_id, min(e.ts) AS t FROM analytics_events e JOIN s%[2]d p ON p.install_id = e.install_id AND e.ts >= p.t WHERE e.name = $%[1]d AND e.ts < $%[3]d GROUP BY e.install_id)`,
				i+1, i, toArg))
		}
		sel = append(sel, fmt.Sprintf(`(SELECT count(*) FROM s%d)`, i+1))
	}
	args := make([]any, 0, n+2)
	for _, s := range steps {
		args = append(args, s)
	}
	args = append(args, from, to)

	counts := make([]int, n)
	dest := make([]any, n)
	for i := range counts {
		dest[i] = &counts[i]
	}
	q := `WITH ` + strings.Join(ctes, ", ") + ` SELECT ` + strings.Join(sel, ", ")
	if err := r.db.QueryRowContext(ctx, q, args...).Scan(dest...); err != nil {
		return nil, fmt.Errorf("AnalyticsFunnel: %w", err)
	}
	return counts, nil
}

// ScreenStat aggregates screen_view events over a window.
type ScreenStat struct {
	Screen   string
	Views    int
	TotalMs  int64
	MedianMs int // views-weighted mean of the daily medians (approximate)
}

func (r *AdminRepository) AnalyticsScreens(ctx context.Context, from, to time.Time) ([]ScreenStat, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT screen, sum(views)::int, sum(total_ms)::bigint, (sum(median_ms::bigint * views) / NULLIF(sum(views), 0))::int
FROM analytics_daily_screens WHERE day BETWEEN $1 AND $2
GROUP BY screen ORDER BY sum(views) DESC`, from, to)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsScreens: %w", err)
	}
	defer rows.Close()
	var out []ScreenStat
	for rows.Next() {
		var s ScreenStat
		var med *int
		if err := rows.Scan(&s.Screen, &s.Views, &s.TotalMs, &med); err != nil {
			return nil, fmt.Errorf("AnalyticsScreens scan: %w", err)
		}
		if med != nil {
			s.MedianMs = *med
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// EventCount is one (day, name) cell of the event counts.
type EventCount struct {
	Day     time.Time
	Name    string
	Count   int
	Uniques int
}

func (r *AdminRepository) AnalyticsEventCounts(ctx context.Context, from, to time.Time, names []string) ([]EventCount, error) {
	q := `SELECT day, name, count, uniques FROM analytics_daily_counts WHERE day BETWEEN $1 AND $2`
	args := []any{from, to}
	if len(names) > 0 {
		q += ` AND name = ANY($3)`
		args = append(args, pq.Array(names))
	}
	rows, err := r.db.QueryContext(ctx, q+` ORDER BY day, name`, args...)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsEventCounts: %w", err)
	}
	defer rows.Close()
	var out []EventCount
	for rows.Next() {
		var e EventCount
		if err := rows.Scan(&e.Day, &e.Name, &e.Count, &e.Uniques); err != nil {
			return nil, fmt.Errorf("AnalyticsEventCounts scan: %w", err)
		}
		e.Day = e.Day.UTC()
		out = append(out, e)
	}
	return out, rows.Err()
}

// TimelineEvent is one raw event in a user's or install's history.
type TimelineEvent struct {
	TS         time.Time
	Name       string
	Screen     string
	Props      json.RawMessage
	SessionID  string
	InstallID  string
	Platform   string
	AppVersion string
}

// AnalyticsInstall is a row of analytics_installs.
type AnalyticsInstall struct {
	InstallID  string
	UserID     string
	FirstSeen  time.Time
	LastSeen   time.Time
	Platform   string
	AppVersion string
}

// AnalyticsTimeline returns events newest first. For a user it covers every
// install linked to the account (so the guest history before signup is
// included) plus events stamped with the user id; for an install, just that
// install. `before` (zero = now) pages backwards.
func (r *AdminRepository) AnalyticsTimeline(ctx context.Context, byUser bool, id string, before time.Time, limit int) ([]TimelineEvent, error) {
	where := `install_id = $1`
	if byUser {
		where = `(install_id IN (SELECT install_id FROM analytics_installs WHERE user_id = $1) OR user_id = $1)`
	}
	args := []any{id, limit}
	if !before.IsZero() {
		where += ` AND ts < $3`
		args = append(args, before)
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT ts, name, COALESCE(screen, ''), props, COALESCE(session_id::text, ''), install_id::text,
       COALESCE(platform, ''), COALESCE(app_version, '')
FROM analytics_events WHERE `+where+` ORDER BY ts DESC, id DESC LIMIT $2`, args...)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsTimeline: %w", err)
	}
	defer rows.Close()
	var out []TimelineEvent
	for rows.Next() {
		var e TimelineEvent
		var props []byte
		if err := rows.Scan(&e.TS, &e.Name, &e.Screen, &props, &e.SessionID, &e.InstallID, &e.Platform, &e.AppVersion); err != nil {
			return nil, fmt.Errorf("AnalyticsTimeline scan: %w", err)
		}
		if len(props) > 0 {
			e.Props = json.RawMessage(props)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// AnalyticsInstallsOf lists the installs linked to a user (byUser) or the one install.
func (r *AdminRepository) AnalyticsInstallsOf(ctx context.Context, byUser bool, id string) ([]AnalyticsInstall, error) {
	where := `install_id = $1`
	if byUser {
		where = `user_id = $1`
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT install_id::text, COALESCE(user_id::text, ''), first_seen, last_seen, COALESCE(platform, ''), COALESCE(app_version, '')
FROM analytics_installs WHERE `+where+` ORDER BY first_seen`, id)
	if err != nil {
		return nil, fmt.Errorf("AnalyticsInstallsOf: %w", err)
	}
	defer rows.Close()
	var out []AnalyticsInstall
	for rows.Next() {
		var i AnalyticsInstall
		if err := rows.Scan(&i.InstallID, &i.UserID, &i.FirstSeen, &i.LastSeen, &i.Platform, &i.AppVersion); err != nil {
			return nil, fmt.Errorf("AnalyticsInstallsOf scan: %w", err)
		}
		i.FirstSeen, i.LastSeen = i.FirstSeen.UTC(), i.LastSeen.UTC()
		out = append(out, i)
	}
	return out, rows.Err()
}
