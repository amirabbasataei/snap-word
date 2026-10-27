package repository

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
	"time"

	"wordchain/backend/internal/config"
)

// AnalyticsRepository stores product-analytics events and their rollups.
type AnalyticsRepository struct {
	db *sql.DB
}

func NewAnalyticsRepository(db *sql.DB) *AnalyticsRepository {
	return &AnalyticsRepository{db: db}
}

// AnalyticsEvent is one validated event ready to insert.
type AnalyticsEvent struct {
	ClientEventID string
	SessionID     string // empty when the client sent none
	Name          string
	Screen        string
	Props         []byte // JSON object, or nil
	TS            time.Time
}

// AnalyticsBatch is one ingest request after validation.
type AnalyticsBatch struct {
	InstallID  string
	UserID     string // from the JWT, never from the body; "" for a guest. Stamped on every event.
	Platform   string
	AppVersion string
	Events     []AnalyticsEvent
}

// InsertAnalyticsEvents stores the batch and upserts the install row in one
// transaction. Events whose (client_event_id, ts) already exist are skipped,
// so a client retry after a lost response is harmless; the return value is the
// number of rows actually inserted.
func (r *AnalyticsRepository) InsertAnalyticsEvents(ctx context.Context, b AnalyticsBatch) (int, error) {
	if len(b.Events) == 0 {
		return 0, nil
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("InsertAnalyticsEvents begin: %w", err)
	}
	defer tx.Rollback()

	minTS, maxTS := b.Events[0].TS, b.Events[0].TS
	var sb strings.Builder
	sb.WriteString(`INSERT INTO analytics_events
  (client_event_id, install_id, user_id, session_id, name, screen, props, ts, app_version, platform) VALUES `)
	args := make([]any, 0, len(b.Events)*10)
	for i, e := range b.Events {
		if e.TS.Before(minTS) {
			minTS = e.TS
		}
		if e.TS.After(maxTS) {
			maxTS = e.TS
		}
		if i > 0 {
			sb.WriteByte(',')
		}
		n := len(args)
		fmt.Fprintf(&sb, "($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)", n+1, n+2, n+3, n+4, n+5, n+6, n+7, n+8, n+9, n+10)
		args = append(args,
			e.ClientEventID, b.InstallID, nullStr(b.UserID), nullStr(e.SessionID), e.Name, nullStr(e.Screen),
			nullBytes(e.Props), e.TS, nullStr(b.AppVersion), nullStr(b.Platform))
	}
	sb.WriteString(` ON CONFLICT (client_event_id, ts) DO NOTHING`)

	res, err := tx.ExecContext(ctx, sb.String(), args...)
	if err != nil {
		return 0, fmt.Errorf("InsertAnalyticsEvents insert: %w", err)
	}
	inserted, _ := res.RowsAffected()

	// first_seen only ever moves earlier and last_seen later, because a batch
	// can carry events queued offline for days.
	_, err = tx.ExecContext(ctx, `
INSERT INTO analytics_installs (install_id, user_id, first_seen, last_seen, platform, app_version)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (install_id) DO UPDATE SET
  user_id     = COALESCE(EXCLUDED.user_id, analytics_installs.user_id),
  first_seen  = LEAST(analytics_installs.first_seen, EXCLUDED.first_seen),
  last_seen   = GREATEST(analytics_installs.last_seen, EXCLUDED.last_seen),
  platform    = COALESCE(EXCLUDED.platform, analytics_installs.platform),
  app_version = COALESCE(EXCLUDED.app_version, analytics_installs.app_version)`,
		b.InstallID, nullStr(b.UserID), config.IranDate(minTS), config.IranDate(maxTS),
		nullStr(b.Platform), nullStr(b.AppVersion))
	if err != nil {
		return 0, fmt.Errorf("InsertAnalyticsEvents install: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("InsertAnalyticsEvents commit: %w", err)
	}
	return int(inserted), nil
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func nullBytes(b []byte) any {
	if len(b) == 0 {
		return nil
	}
	return string(b)
}

const analyticsPartitionPrefix = "analytics_events_"

var analyticsPartitionRe = regexp.MustCompile(`^analytics_events_(\d{4})(\d{2})$`)

// monthStart returns midnight UTC on the first day of t's UTC month.
func monthStart(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), 1, 0, 0, 0, 0, time.UTC)
}

// EnsureAnalyticsPartitions creates the monthly partitions from the month
// before `now` through `ahead` months after it (existing ones are left alone).
func (r *AnalyticsRepository) EnsureAnalyticsPartitions(ctx context.Context, now time.Time, ahead int) error {
	first := monthStart(now).AddDate(0, -1, 0)
	for i := 0; i <= ahead+1; i++ {
		m := first.AddDate(0, i, 0)
		// The name and bounds are formatted from a time.Time, never from input.
		q := fmt.Sprintf(`CREATE TABLE IF NOT EXISTS %s%s PARTITION OF analytics_events FOR VALUES FROM ('%s') TO ('%s')`,
			analyticsPartitionPrefix, m.Format("200601"), m.Format("2006-01-02"), m.AddDate(0, 1, 0).Format("2006-01-02"))
		if _, err := r.db.ExecContext(ctx, q); err != nil {
			return fmt.Errorf("EnsureAnalyticsPartitions %s: %w", m.Format("200601"), err)
		}
	}
	return nil
}

// DropOldAnalyticsPartitions drops raw-event partitions whose whole month ended
// before cutoff and returns their names. Rollups are untouched.
func (r *AnalyticsRepository) DropOldAnalyticsPartitions(ctx context.Context, cutoff time.Time) ([]string, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT c.relname FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
JOIN pg_class p ON p.oid = i.inhparent
WHERE p.relname = 'analytics_events'`)
	if err != nil {
		return nil, fmt.Errorf("DropOldAnalyticsPartitions list: %w", err)
	}
	var old []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return nil, fmt.Errorf("DropOldAnalyticsPartitions scan: %w", err)
		}
		m := analyticsPartitionRe.FindStringSubmatch(name)
		if m == nil {
			continue
		}
		var y, mo int
		fmt.Sscanf(m[1]+" "+m[2], "%d %d", &y, &mo)
		end := time.Date(y, time.Month(mo), 1, 0, 0, 0, 0, time.UTC).AddDate(0, 1, 0)
		if !end.After(cutoff) {
			old = append(old, name)
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, fmt.Errorf("DropOldAnalyticsPartitions rows: %w", err)
	}
	rows.Close()

	for _, name := range old {
		// name matched analyticsPartitionRe above, so it is safe to splice.
		if _, err := r.db.ExecContext(ctx, `DROP TABLE IF EXISTS `+name); err != nil {
			return nil, fmt.Errorf("DropOldAnalyticsPartitions drop %s: %w", name, err)
		}
	}
	return old, nil
}

// RollupAnalyticsDay rebuilds every rollup row of one Iran calendar day from
// the raw events. It is idempotent: the day's rows are replaced in one
// transaction, so it is safe to run repeatedly (live "today", late uploads).
func (r *AnalyticsRepository) RollupAnalyticsDay(ctx context.Context, day time.Time) error {
	d := day.UTC()
	start := time.Date(d.Year(), d.Month(), d.Day(), 0, 0, 0, 0, config.IranLocation)
	end := start.Add(24 * time.Hour)

	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("RollupAnalyticsDay begin: %w", err)
	}
	defer tx.Rollback()

	for _, t := range []string{"analytics_daily_active", "analytics_daily_counts", "analytics_daily_screens", "analytics_daily_sessions"} {
		if _, err := tx.ExecContext(ctx, `DELETE FROM `+t+` WHERE day = $1`, config.IranDate(start)); err != nil {
			return fmt.Errorf("RollupAnalyticsDay clear %s: %w", t, err)
		}
	}

	stmts := []struct{ name, q string }{
		{"active", `
INSERT INTO analytics_daily_active (day, install_id, user_id, events)
SELECT $1::date, install_id, (array_agg(user_id) FILTER (WHERE user_id IS NOT NULL))[1], count(*)
FROM analytics_events WHERE ts >= $2 AND ts < $3 GROUP BY install_id`},
		{"counts", `
INSERT INTO analytics_daily_counts (day, name, count, uniques)
SELECT $1::date, name, count(*), count(DISTINCT install_id)
FROM analytics_events WHERE ts >= $2 AND ts < $3 GROUP BY name`},
		{"screens", `
INSERT INTO analytics_daily_screens (day, screen, views, total_ms, median_ms)
SELECT $1::date, screen, count(*), COALESCE(sum(ms), 0)::bigint,
       COALESCE(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms), 0)::int
FROM (
  SELECT screen, CASE WHEN props->>'duration_ms' ~ '^[0-9]{1,10}$' THEN (props->>'duration_ms')::bigint END AS ms
  FROM analytics_events
  WHERE name = 'screen_view' AND screen IS NOT NULL AND ts >= $2 AND ts < $3
) v GROUP BY screen`},
		{"sessions", `
INSERT INTO analytics_daily_sessions (day, sessions, total_ms)
SELECT $1::date, count(*), COALESCE(sum(CASE WHEN props->>'duration_ms' ~ '^[0-9]{1,10}$' THEN (props->>'duration_ms')::bigint END), 0)::bigint
FROM analytics_events WHERE name = 'session_end' AND ts >= $2 AND ts < $3
HAVING count(*) > 0`},
	}
	for _, s := range stmts {
		if _, err := tx.ExecContext(ctx, s.q, config.IranDate(start), start, end); err != nil {
			return fmt.Errorf("RollupAnalyticsDay %s: %w", s.name, err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("RollupAnalyticsDay commit: %w", err)
	}
	return nil
}
