package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/lib/pq"

	"wordchain/backend/internal/config"
)

var (
	ErrCampaignNotFound  = errors.New("campaign not found")
	ErrCampaignDuplicate = errors.New("an identical notification was just sent")
)

// Audience kinds.
const (
	AudienceAll     = "all"
	AudienceSegment = "segment"
	AudienceUsers   = "users"
)

// NotifSegment filters accounts for a group send. Zero values mean "any".
type NotifSegment struct {
	Premium          string `json:"premium"`            // any | yes | no
	Activity         string `json:"activity"`           // any | active | inactive (last game within / before Days)
	Days             int    `json:"days"`               // window for Activity
	JoinedWithinDays int    `json:"joined_within_days"` // 0 = any
	Push             string `json:"push"`               // any | enabled (a device with the permission granted) | disabled
}

// NotifAudience says who a campaign goes to. Banned accounts, unfinished
// signups and the system AI user are never recipients, whatever the type.
type NotifAudience struct {
	Type    string        `json:"type"`
	Segment *NotifSegment `json:"segment,omitempty"`
	UserIDs []string      `json:"user_ids,omitempty"`
}

// pushStateSub reduces each user's devices to one permission state, best first.
const pushStateSub = `
SELECT user_id,
       CASE WHEN bool_or(permission = 'granted') THEN 'granted'
            WHEN bool_or(permission = 'unknown') THEN 'unknown'
            WHEN bool_or(permission = 'denied')  THEN 'denied'
            ELSE 'not_determined' END AS state
FROM device_tokens GROUP BY user_id`

const audienceFrom = `
FROM users u
LEFT JOIN player_stats ps ON ps.user_id = u.id
LEFT JOIN (` + pushStateSub + `) pst ON pst.user_id = u.id`

// audienceWhere builds the WHERE clause (aliases u, ps, pst) and its args.
func audienceWhere(a NotifAudience, today time.Time) (string, []any, error) {
	args := []any{config.SystemAIUserID}
	conds := []string{"u.phone_verified_at IS NOT NULL", "u.banned_at IS NULL", "u.id <> $1"}
	add := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	switch a.Type {
	case AudienceAll:
	case AudienceUsers:
		if len(a.UserIDs) == 0 {
			return "", nil, fmt.Errorf("audience users: empty list")
		}
		conds = append(conds, "u.id = ANY("+add(pq.Array(a.UserIDs))+"::uuid[])")
	case AudienceSegment:
		s := a.Segment
		if s == nil {
			return "", nil, fmt.Errorf("audience segment: missing filters")
		}
		switch s.Premium {
		case "yes":
			conds = append(conds, "u.premium_until > now()")
		case "no":
			conds = append(conds, "(u.premium_until IS NULL OR u.premium_until <= now())")
		}
		since := today.AddDate(0, 0, -s.Days).Format("2006-01-02")
		switch s.Activity {
		case "active":
			conds = append(conds, "ps.last_played_date >= "+add(since)+"::date")
		case "inactive":
			conds = append(conds, "(ps.last_played_date IS NULL OR ps.last_played_date < "+add(since)+"::date)")
		}
		if s.JoinedWithinDays > 0 {
			conds = append(conds, "u.created_at >= now() - make_interval(days => "+add(s.JoinedWithinDays)+")")
		}
		switch s.Push {
		case "enabled":
			conds = append(conds, "pst.state = 'granted'")
		case "disabled":
			conds = append(conds, "COALESCE(pst.state, 'none') <> 'granted'")
		}
	default:
		return "", nil, fmt.Errorf("unknown audience type %q", a.Type)
	}
	return strings.Join(conds, " AND "), args, nil
}

// AudienceCounts is how many accounts an audience matches and what the OS
// permission looks like among them.
type AudienceCounts struct {
	Recipients    int
	Granted       int // at least one device with notifications allowed
	Unknown       int // only devices registered before permission was reported
	Denied        int
	NotDetermined int // the OS prompt was never answered
	None          int // no device registered (guest-turned-account who never allowed / never opened the app signed in)
}

// CountAudience sizes an audience without sending anything.
func (r *AdminRepository) CountAudience(ctx context.Context, a NotifAudience, today time.Time) (*AudienceCounts, error) {
	where, args, err := audienceWhere(a, today)
	if err != nil {
		return nil, err
	}
	q := `SELECT count(*),
       count(*) FILTER (WHERE pst.state = 'granted'),
       count(*) FILTER (WHERE pst.state = 'unknown'),
       count(*) FILTER (WHERE pst.state = 'denied'),
       count(*) FILTER (WHERE pst.state = 'not_determined'),
       count(*) FILTER (WHERE pst.state IS NULL)` + audienceFrom + ` WHERE ` + where
	var c AudienceCounts
	if err := r.db.QueryRowContext(ctx, q, args...).Scan(
		&c.Recipients, &c.Granted, &c.Unknown, &c.Denied, &c.NotDetermined, &c.None,
	); err != nil {
		return nil, fmt.Errorf("AdminRepository.CountAudience: %w", err)
	}
	return &c, nil
}

// PushTargets lists the devices a push to this audience would be sent to:
// every device whose permission is granted, or unknown (an app version that
// predates the permission report — sending is harmless if it is off).
func (r *AdminRepository) PushTargets(ctx context.Context, a NotifAudience, today time.Time) ([]DeviceToken, error) {
	where, args, err := audienceWhere(a, today)
	if err != nil {
		return nil, err
	}
	q := `SELECT t.user_id, t.token, t.platform` + audienceFrom +
		` JOIN device_tokens t ON t.user_id = u.id WHERE t.permission IN ('granted', 'unknown') AND ` + where
	rows, err := r.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.PushTargets: %w", err)
	}
	defer rows.Close()
	var out []DeviceToken
	for rows.Next() {
		var d DeviceToken
		if err := rows.Scan(&d.UserID, &d.Token, &d.Platform); err != nil {
			return nil, fmt.Errorf("AdminRepository.PushTargets scan: %w", err)
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// NotifCampaign is one admin send.
type NotifCampaign struct {
	ID             string
	Title          string
	Body           string
	Route          string
	Push           bool
	Inapp          bool
	Audience       NotifAudience
	CreatedBy      string
	CreatedAt      time.Time
	Recipients     int
	InappDelivered int
	InappRead      int
	PushStatus     string
	PushUsers      int
	PushDevices    int
	PushSent       int
	PushFailed     int
	PushRemoved    int
	PushFinishedAt *time.Time
}

// NotifCampaignInput is what the service hands over to be stored and fanned out.
type NotifCampaignInput struct {
	Title, Body, Route string
	Push, Inapp        bool
	Audience           NotifAudience
	CreatedBy          string
}

// CreateCampaign stores the campaign and, for in-app sends, creates every
// recipient's inbox row in the same transaction. Push delivery is left to the
// caller (status starts as "sending" when Push is set).
func (r *AdminRepository) CreateCampaign(ctx context.Context, in NotifCampaignInput, today time.Time) (*NotifCampaign, error) {
	where, args, err := audienceWhere(in.Audience, today)
	if err != nil {
		return nil, err
	}
	audJSON, err := json.Marshal(in.Audience)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign marshal: %w", err)
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign begin: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	var dup bool
	if err := tx.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM notification_campaigns
		   WHERE title = $1 AND body = $2 AND created_at > now() - make_interval(secs => $3))`,
		in.Title, in.Body, config.NotifDuplicateWindow.Seconds()).Scan(&dup); err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign dup check: %w", err)
	}
	if dup {
		return nil, ErrCampaignDuplicate
	}

	pushStatus := "none"
	if in.Push {
		pushStatus = "sending"
	}
	c := &NotifCampaign{
		Title: in.Title, Body: in.Body, Route: in.Route, Push: in.Push, Inapp: in.Inapp,
		Audience: in.Audience, CreatedBy: in.CreatedBy, PushStatus: pushStatus,
	}
	if err := tx.QueryRowContext(ctx,
		`INSERT INTO notification_campaigns (title, body, route, push, inapp, audience_type, audience, created_by, push_status)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id, created_at`,
		in.Title, in.Body, in.Route, in.Push, in.Inapp, in.Audience.Type, audJSON, in.CreatedBy, pushStatus,
	).Scan(&c.ID, &c.CreatedAt); err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign insert: %w", err)
	}

	if in.Inapp {
		fan := append(append([]any{}, args...), c.ID)
		res, err := tx.ExecContext(ctx,
			fmt.Sprintf(`INSERT INTO inbox_messages (campaign_id, user_id) SELECT $%d::uuid, u.id`, len(fan))+
				audienceFrom+` WHERE `+where, fan...)
		if err != nil {
			return nil, fmt.Errorf("AdminRepository.CreateCampaign fan-out: %w", err)
		}
		n, _ := res.RowsAffected()
		c.InappDelivered = int(n)
		c.Recipients = c.InappDelivered
	}
	if !in.Inapp {
		if err := tx.QueryRowContext(ctx, `SELECT count(*)`+audienceFrom+` WHERE `+where, args...).Scan(&c.Recipients); err != nil {
			return nil, fmt.Errorf("AdminRepository.CreateCampaign count: %w", err)
		}
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE notification_campaigns SET recipients = $2, inapp_delivered = $3 WHERE id = $1`,
		c.ID, c.Recipients, c.InappDelivered); err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign counts: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("AdminRepository.CreateCampaign commit: %w", err)
	}
	return c, nil
}

// PushOutcome is the result of delivering one campaign's push.
type PushOutcome struct {
	Status                                string // done | failed
	Users, Devices, Sent, Failed, Removed int
}

// FinishPush records how the push delivery went.
func (r *AdminRepository) FinishPush(ctx context.Context, id string, o PushOutcome) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE notification_campaigns
		    SET push_status = $2, push_users = $3, push_devices = $4, push_sent = $5,
		        push_failed = $6, push_removed = $7, push_finished_at = now()
		  WHERE id = $1`,
		id, o.Status, o.Users, o.Devices, o.Sent, o.Failed, o.Removed)
	if err != nil {
		return fmt.Errorf("AdminRepository.FinishPush: %w", err)
	}
	return nil
}

// FailStaleCampaigns marks pushes a previous process was still delivering when
// it stopped, so the history never shows "sending" forever.
func (r *AdminRepository) FailStaleCampaigns(ctx context.Context) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE notification_campaigns SET push_status = 'interrupted', push_finished_at = now() WHERE push_status = 'sending'`)
	if err != nil {
		return fmt.Errorf("AdminRepository.FailStaleCampaigns: %w", err)
	}
	return nil
}

const campaignCols = `c.id, c.title, c.body, c.route, c.push, c.inapp, c.audience, c.created_by, c.created_at,
       c.recipients, c.inapp_delivered,
       (SELECT count(*) FROM inbox_messages m WHERE m.campaign_id = c.id AND m.read_at IS NOT NULL),
       c.push_status, c.push_users, c.push_devices, c.push_sent, c.push_failed, c.push_removed, c.push_finished_at`

type rowScanner interface{ Scan(dest ...any) error }

func scanCampaign(s rowScanner) (*NotifCampaign, error) {
	var (
		c        NotifCampaign
		audience []byte
		finished sql.NullTime
	)
	if err := s.Scan(&c.ID, &c.Title, &c.Body, &c.Route, &c.Push, &c.Inapp, &audience, &c.CreatedBy, &c.CreatedAt,
		&c.Recipients, &c.InappDelivered, &c.InappRead,
		&c.PushStatus, &c.PushUsers, &c.PushDevices, &c.PushSent, &c.PushFailed, &c.PushRemoved, &finished); err != nil {
		return nil, err
	}
	_ = json.Unmarshal(audience, &c.Audience)
	if finished.Valid {
		c.PushFinishedAt = &finished.Time
	}
	return &c, nil
}

// ListCampaigns returns the history, newest first.
func (r *AdminRepository) ListCampaigns(ctx context.Context, page, size int) ([]NotifCampaign, int, error) {
	var total int
	if err := r.db.QueryRowContext(ctx, `SELECT count(*) FROM notification_campaigns`).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListCampaigns count: %w", err)
	}
	rows, err := r.db.QueryContext(ctx,
		`SELECT `+campaignCols+` FROM notification_campaigns c ORDER BY c.created_at DESC LIMIT $1 OFFSET $2`,
		size, (page-1)*size)
	if err != nil {
		return nil, 0, fmt.Errorf("AdminRepository.ListCampaigns: %w", err)
	}
	defer rows.Close()
	out := []NotifCampaign{}
	for rows.Next() {
		c, err := scanCampaign(rows)
		if err != nil {
			return nil, 0, fmt.Errorf("AdminRepository.ListCampaigns scan: %w", err)
		}
		out = append(out, *c)
	}
	return out, total, rows.Err()
}

// GetCampaign loads one campaign, or ErrCampaignNotFound.
func (r *AdminRepository) GetCampaign(ctx context.Context, id string) (*NotifCampaign, error) {
	c, err := scanCampaign(r.db.QueryRowContext(ctx, `SELECT `+campaignCols+` FROM notification_campaigns c WHERE c.id = $1`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrCampaignNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.GetCampaign: %w", err)
	}
	return c, nil
}

// NotifUser is an account named in a "specific users" campaign.
type NotifUser struct {
	ID       string
	Username string
	Read     *time.Time // in-app read time, when the campaign had an in-app message
}

// CampaignUsers resolves the accounts of a "specific users" campaign.
func (r *AdminRepository) CampaignUsers(ctx context.Context, id string, userIDs []string) ([]NotifUser, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT u.id, COALESCE(u.username, ''), m.read_at
		   FROM users u LEFT JOIN inbox_messages m ON m.user_id = u.id AND m.campaign_id = $1
		  WHERE u.id = ANY($2::uuid[]) ORDER BY u.username`, id, pq.Array(userIDs))
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.CampaignUsers: %w", err)
	}
	defer rows.Close()
	out := []NotifUser{}
	for rows.Next() {
		var u NotifUser
		var read sql.NullTime
		if err := rows.Scan(&u.ID, &u.Username, &read); err != nil {
			return nil, fmt.Errorf("AdminRepository.CampaignUsers scan: %w", err)
		}
		if read.Valid {
			u.Read = &read.Time
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// PushReach is the whole-population view of who can be pushed.
type PushReach struct {
	Users         int
	Granted       int
	Unknown       int
	Denied        int
	NotDetermined int
	None          int
	Devices       []PushDeviceCount
}

// PushDeviceCount is the number of registered devices per platform and permission.
type PushDeviceCount struct {
	Platform   string
	Permission string
	Count      int
}

// PushReach counts accounts by their best push-permission state, plus devices.
func (r *AdminRepository) PushReach(ctx context.Context) (*PushReach, error) {
	var p PushReach
	if err := r.db.QueryRowContext(ctx,
		`SELECT count(*),
		        count(*) FILTER (WHERE pst.state = 'granted'),
		        count(*) FILTER (WHERE pst.state = 'unknown'),
		        count(*) FILTER (WHERE pst.state = 'denied'),
		        count(*) FILTER (WHERE pst.state = 'not_determined'),
		        count(*) FILTER (WHERE pst.state IS NULL)
		   FROM users u LEFT JOIN (`+pushStateSub+`) pst ON pst.user_id = u.id
		  WHERE u.phone_verified_at IS NOT NULL AND u.banned_at IS NULL AND u.id <> $1`,
		config.SystemAIUserID,
	).Scan(&p.Users, &p.Granted, &p.Unknown, &p.Denied, &p.NotDetermined, &p.None); err != nil {
		return nil, fmt.Errorf("AdminRepository.PushReach: %w", err)
	}
	rows, err := r.db.QueryContext(ctx,
		`SELECT platform, permission, count(*) FROM device_tokens GROUP BY 1, 2 ORDER BY 1, 2`)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.PushReach devices: %w", err)
	}
	defer rows.Close()
	p.Devices = []PushDeviceCount{}
	for rows.Next() {
		var d PushDeviceCount
		if err := rows.Scan(&d.Platform, &d.Permission, &d.Count); err != nil {
			return nil, fmt.Errorf("AdminRepository.PushReach devices scan: %w", err)
		}
		p.Devices = append(p.Devices, d)
	}
	return &p, rows.Err()
}

// PushDevice is one registered device of a user (the token itself is never exposed).
type PushDevice struct {
	Platform   string
	Permission string
	UpdatedAt  time.Time
}

// UserPushDevices lists a user's registered devices, most recently seen first.
func (r *AdminRepository) UserPushDevices(ctx context.Context, userID string) ([]PushDevice, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT platform, permission, updated_at FROM device_tokens WHERE user_id = $1 ORDER BY updated_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.UserPushDevices: %w", err)
	}
	defer rows.Close()
	out := []PushDevice{}
	for rows.Next() {
		var d PushDevice
		if err := rows.Scan(&d.Platform, &d.Permission, &d.UpdatedAt); err != nil {
			return nil, fmt.Errorf("AdminRepository.UserPushDevices scan: %w", err)
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// ExistingUserIDs returns which of ids are signed-up, non-banned accounts.
func (r *AdminRepository) ExistingUserIDs(ctx context.Context, ids []string) (map[string]bool, error) {
	rows, err := r.db.QueryContext(ctx,
		`SELECT id FROM users WHERE id = ANY($1::uuid[]) AND phone_verified_at IS NOT NULL AND banned_at IS NULL AND id <> $2`,
		pq.Array(ids), config.SystemAIUserID)
	if err != nil {
		return nil, fmt.Errorf("AdminRepository.ExistingUserIDs: %w", err)
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("AdminRepository.ExistingUserIDs scan: %w", err)
		}
		out[id] = true
	}
	return out, rows.Err()
}
