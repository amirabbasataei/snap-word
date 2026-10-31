package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// Sentinel errors for the admin notification endpoints; the handler maps them to codes.
var (
	ErrNotifTitle         = errors.New("notification title is empty or too long")
	ErrNotifBody          = errors.New("notification body is empty or too long")
	ErrNotifChannels      = errors.New("choose push, in-app, or both")
	ErrNotifRoute         = errors.New("unknown deep link")
	ErrNotifAudience      = errors.New("invalid audience")
	ErrNotifUnknownUser   = errors.New("an addressed user does not exist or is banned")
	ErrNotifFCMOff        = errors.New("push is not configured on the server")
	ErrNotifNoRecipients  = errors.New("the audience matches nobody")
	ErrNotifNoDeliverable = errors.New("nobody in the audience can receive a push")
	ErrNotifDuplicate     = repository.ErrCampaignDuplicate
	ErrNotifNotFound      = repository.ErrCampaignNotFound
)

type notifStore interface {
	CountAudience(ctx context.Context, a repository.NotifAudience, today time.Time) (*repository.AudienceCounts, error)
	PushTargets(ctx context.Context, a repository.NotifAudience, today time.Time) ([]repository.DeviceToken, error)
	CreateCampaign(ctx context.Context, in repository.NotifCampaignInput, today time.Time) (*repository.NotifCampaign, error)
	FinishPush(ctx context.Context, id string, o repository.PushOutcome) error
	ListCampaigns(ctx context.Context, page, size int) ([]repository.NotifCampaign, int, error)
	GetCampaign(ctx context.Context, id string) (*repository.NotifCampaign, error)
	CampaignUsers(ctx context.Context, id string, userIDs []string) ([]repository.NotifUser, error)
	PushReach(ctx context.Context) (*repository.PushReach, error)
	ExistingUserIDs(ctx context.Context, ids []string) (map[string]bool, error)
}

type pushSender interface {
	Configured() bool
	SendBatch(ctx context.Context, targets []PushTarget, title, body, route string) PushResult
}

// AdminNotificationService backs the panel's «اعلان‌ها» page: sizing an
// audience, sending a push and/or in-app message to everyone, a group or
// specific users, the send history, and the push-permission overview.
type AdminNotificationService struct {
	store notifStore
	push  pushSender
	audit *AuditService
	now   func() time.Time
	wg    sync.WaitGroup // in-flight background deliveries (tests wait on it)
}

func NewAdminNotificationService(store notifStore, push pushSender, audit *AuditService) *AdminNotificationService {
	return &AdminNotificationService{store: store, push: push, audit: audit, now: time.Now}
}

// Wait blocks until every background push delivery has finished.
func (s *AdminNotificationService) Wait() { s.wg.Wait() }

// NotifPreview sizes an audience and says how many of them a push can reach.
type NotifPreview struct {
	Recipients    int  `json:"recipients"`
	FCMConfigured bool `json:"fcm_configured"`
	Push          struct {
		Deliverable   int `json:"deliverable"` // granted + unknown
		Granted       int `json:"granted"`
		Unknown       int `json:"unknown"`
		Denied        int `json:"denied"`
		NotDetermined int `json:"not_determined"`
		None          int `json:"none"`
	} `json:"push"`
}

func previewOf(c *repository.AudienceCounts, fcm bool) *NotifPreview {
	p := &NotifPreview{Recipients: c.Recipients, FCMConfigured: fcm}
	p.Push.Granted, p.Push.Unknown, p.Push.Denied = c.Granted, c.Unknown, c.Denied
	p.Push.NotDetermined, p.Push.None = c.NotDetermined, c.None
	p.Push.Deliverable = c.Granted + c.Unknown
	return p
}

// normalizeAudience validates the audience and returns the canonical form that
// is stored with the campaign.
func (s *AdminNotificationService) normalizeAudience(ctx context.Context, a repository.NotifAudience) (repository.NotifAudience, error) {
	switch a.Type {
	case repository.AudienceAll:
		return repository.NotifAudience{Type: repository.AudienceAll}, nil
	case repository.AudienceSegment:
		in := a.Segment
		if in == nil {
			return a, ErrNotifAudience
		}
		seg := repository.NotifSegment{Premium: in.Premium, Activity: in.Activity, Days: in.Days,
			JoinedWithinDays: in.JoinedWithinDays, Push: in.Push}
		if seg.Premium == "" {
			seg.Premium = "any"
		}
		if seg.Activity == "" {
			seg.Activity = "any"
		}
		if seg.Push == "" {
			seg.Push = "any"
		}
		if !slices.Contains([]string{"any", "yes", "no"}, seg.Premium) ||
			!slices.Contains([]string{"any", "active", "inactive"}, seg.Activity) ||
			!slices.Contains([]string{"any", "enabled", "disabled"}, seg.Push) ||
			seg.JoinedWithinDays < 0 || seg.JoinedWithinDays > 3650 {
			return a, ErrNotifAudience
		}
		if seg.Activity == "any" {
			seg.Days = 0
		} else if seg.Days < 1 || seg.Days > 365 {
			return a, ErrNotifAudience
		}
		return repository.NotifAudience{Type: repository.AudienceSegment, Segment: &seg}, nil
	case repository.AudienceUsers:
		seen := map[string]bool{}
		ids := []string{}
		for _, id := range a.UserIDs {
			id = strings.ToLower(strings.TrimSpace(id))
			if !uuidRe.MatchString(id) {
				return a, ErrNotifAudience
			}
			if !seen[id] {
				seen[id] = true
				ids = append(ids, id)
			}
		}
		if len(ids) == 0 || len(ids) > config.NotifMaxTargetUsers {
			return a, ErrNotifAudience
		}
		found, err := s.store.ExistingUserIDs(ctx, ids)
		if err != nil {
			return a, fmt.Errorf("AdminNotificationService.normalizeAudience: %w", err)
		}
		for _, id := range ids {
			if !found[id] {
				return a, ErrNotifUnknownUser
			}
		}
		return repository.NotifAudience{Type: repository.AudienceUsers, UserIDs: ids}, nil
	}
	return a, ErrNotifAudience
}

func (s *AdminNotificationService) today() time.Time { return config.IranDate(s.now()) }

// Preview counts the audience without sending anything.
func (s *AdminNotificationService) Preview(ctx context.Context, a repository.NotifAudience) (*NotifPreview, error) {
	a, err := s.normalizeAudience(ctx, a)
	if err != nil {
		return nil, err
	}
	c, err := s.store.CountAudience(ctx, a, s.today())
	if err != nil {
		return nil, fmt.Errorf("AdminNotificationService.Preview: %w", err)
	}
	return previewOf(c, s.push.Configured()), nil
}

// NotifSendInput is a send request from the panel.
type NotifSendInput struct {
	Title    string
	Body     string
	Route    string
	Channels []string // "push", "inapp"
	Audience repository.NotifAudience
}

// NotifCampaignView is a campaign as the panel shows it.
type NotifCampaignView struct {
	ID             string                   `json:"id"`
	Title          string                   `json:"title"`
	Body           string                   `json:"body"`
	Route          string                   `json:"route"`
	Push           bool                     `json:"push"`
	Inapp          bool                     `json:"inapp"`
	Audience       repository.NotifAudience `json:"audience"`
	CreatedBy      string                   `json:"created_by"`
	CreatedAt      time.Time                `json:"created_at"`
	Recipients     int                      `json:"recipients"`
	InappDelivered int                      `json:"inapp_delivered"`
	InappRead      int                      `json:"inapp_read"`
	PushStatus     string                   `json:"push_status"`
	PushUsers      int                      `json:"push_users"`
	PushDevices    int                      `json:"push_devices"`
	PushSent       int                      `json:"push_sent"`
	PushFailed     int                      `json:"push_failed"`
	PushRemoved    int                      `json:"push_removed"`
	PushFinishedAt *time.Time               `json:"push_finished_at"`
}

func viewOf(c *repository.NotifCampaign) NotifCampaignView {
	return NotifCampaignView{
		ID: c.ID, Title: c.Title, Body: c.Body, Route: c.Route, Push: c.Push, Inapp: c.Inapp,
		Audience: c.Audience, CreatedBy: c.CreatedBy, CreatedAt: c.CreatedAt,
		Recipients: c.Recipients, InappDelivered: c.InappDelivered, InappRead: c.InappRead,
		PushStatus: c.PushStatus, PushUsers: c.PushUsers, PushDevices: c.PushDevices,
		PushSent: c.PushSent, PushFailed: c.PushFailed, PushRemoved: c.PushRemoved, PushFinishedAt: c.PushFinishedAt,
	}
}

// Send validates, stores and delivers a notification. In-app messages exist
// when this returns; the push is delivered in the background and its outcome is
// written to the campaign when finished.
func (s *AdminNotificationService) Send(ctx context.Context, actor AuditActor, in NotifSendInput) (*NotifCampaignView, error) {
	title, body := strings.TrimSpace(in.Title), strings.TrimSpace(in.Body)
	if n := utf8.RuneCountInString(title); n == 0 || n > config.NotifTitleMaxRunes {
		return nil, ErrNotifTitle
	}
	if n := utf8.RuneCountInString(body); n == 0 || n > config.NotifBodyMaxRunes {
		return nil, ErrNotifBody
	}
	if in.Route != "" && !slices.Contains(config.NotifRoutes, in.Route) {
		return nil, ErrNotifRoute
	}
	var push, inapp bool
	for _, ch := range in.Channels {
		switch ch {
		case "push":
			push = true
		case "inapp":
			inapp = true
		default:
			return nil, ErrNotifChannels
		}
	}
	if !push && !inapp {
		return nil, ErrNotifChannels
	}
	if push && !s.push.Configured() {
		return nil, ErrNotifFCMOff
	}
	aud, err := s.normalizeAudience(ctx, in.Audience)
	if err != nil {
		return nil, err
	}
	counts, err := s.store.CountAudience(ctx, aud, s.today())
	if err != nil {
		return nil, fmt.Errorf("AdminNotificationService.Send: %w", err)
	}
	if counts.Recipients == 0 {
		return nil, ErrNotifNoRecipients
	}
	if !inapp && counts.Granted+counts.Unknown == 0 {
		return nil, ErrNotifNoDeliverable
	}

	c, err := s.store.CreateCampaign(ctx, repository.NotifCampaignInput{
		Title: title, Body: body, Route: in.Route, Push: push, Inapp: inapp,
		Audience: aud, CreatedBy: actor.Name,
	}, s.today())
	if err != nil {
		return nil, err
	}
	s.audit.LogRecord(ctx, actor, "notification.send", AuditTarget{Type: "notification", ID: c.ID}, map[string]any{
		"title": title, "push": push, "inapp": inapp, "audience": aud.Type, "recipients": c.Recipients,
	})
	if push {
		s.wg.Add(1)
		go s.deliverPush(context.WithoutCancel(ctx), c.ID, aud, title, body, in.Route)
	}
	v := viewOf(c)
	return &v, nil
}

// deliverPush resolves the devices, sends, and records the outcome.
func (s *AdminNotificationService) deliverPush(ctx context.Context, id string, aud repository.NotifAudience, title, body, route string) {
	defer s.wg.Done()
	ctx, cancel := context.WithTimeout(ctx, config.NotifPushTimeout)
	defer cancel()

	out := repository.PushOutcome{Status: "failed"}
	defer func() {
		// The campaign must leave "sending" even when the request context is long gone.
		fin, cancelFin := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancelFin()
		if err := s.store.FinishPush(fin, id, out); err != nil {
			slog.Error("notification campaign: could not record push outcome", "campaign", id, "error", err)
		}
	}()

	devices, err := s.store.PushTargets(ctx, aud, s.today())
	if err != nil {
		slog.Error("notification campaign: resolving devices failed", "campaign", id, "error", err)
		return
	}
	targets := make([]PushTarget, len(devices))
	for i, d := range devices {
		targets[i] = PushTarget{UserID: d.UserID, Token: d.Token}
	}
	res := s.push.SendBatch(ctx, targets, title, body, route)
	out = repository.PushOutcome{Status: "done", Users: res.Users, Devices: res.Devices,
		Sent: res.Sent, Failed: res.Failed, Removed: res.Removed}
	if res.Devices > 0 && res.Sent == 0 {
		out.Status = "failed"
	}
	slog.Info("notification campaign pushed", "campaign", id, "devices", res.Devices, "sent", res.Sent, "failed", res.Failed, "removed", res.Removed)
}

// NotifPage is one page of the send history.
type NotifPage struct {
	Items    []NotifCampaignView `json:"items"`
	Total    int                 `json:"total"`
	Page     int                 `json:"page"`
	PageSize int                 `json:"page_size"`
}

// List returns the send history, newest first.
func (s *AdminNotificationService) List(ctx context.Context, page, size int) (*NotifPage, error) {
	if page < 1 {
		page = 1
	}
	if size < 1 {
		size = config.NotifPageSizeDefault
	}
	size = min(size, config.NotifPageSizeMax)
	rows, total, err := s.store.ListCampaigns(ctx, page, size)
	if err != nil {
		return nil, fmt.Errorf("AdminNotificationService.List: %w", err)
	}
	out := &NotifPage{Items: make([]NotifCampaignView, len(rows)), Total: total, Page: page, PageSize: size}
	for i := range rows {
		out.Items[i] = viewOf(&rows[i])
	}
	return out, nil
}

// NotifUserView is a named recipient of a "specific users" send.
type NotifUserView struct {
	ID       string     `json:"id"`
	Username string     `json:"username"`
	ReadAt   *time.Time `json:"read_at"`
}

// NotifDetail is a campaign plus, for a "specific users" send, who got it.
type NotifDetail struct {
	NotifCampaignView
	Users []NotifUserView `json:"users"`
}

// Get loads one campaign.
func (s *AdminNotificationService) Get(ctx context.Context, id string) (*NotifDetail, error) {
	if !uuidRe.MatchString(id) {
		return nil, ErrNotifNotFound
	}
	c, err := s.store.GetCampaign(ctx, id)
	if err != nil {
		return nil, err
	}
	out := &NotifDetail{NotifCampaignView: viewOf(c), Users: []NotifUserView{}}
	if c.Audience.Type == repository.AudienceUsers {
		users, err := s.store.CampaignUsers(ctx, id, c.Audience.UserIDs)
		if err != nil {
			return nil, fmt.Errorf("AdminNotificationService.Get: %w", err)
		}
		for _, u := range users {
			out.Users = append(out.Users, NotifUserView{ID: u.ID, Username: u.Username, ReadAt: u.Read})
		}
	}
	return out, nil
}

// NotifReach answers "who can we push at all?" for the whole player base.
type NotifReach struct {
	FCMConfigured bool `json:"fcm_configured"`
	Users         int  `json:"users"`
	Deliverable   int  `json:"deliverable"`
	Granted       int  `json:"granted"`
	Unknown       int  `json:"unknown"`
	Denied        int  `json:"denied"`
	NotDetermined int  `json:"not_determined"`
	None          int  `json:"none"`
	Devices       []struct {
		Platform   string `json:"platform"`
		Permission string `json:"permission"`
		Count      int    `json:"count"`
	} `json:"devices"`
}

// Reach counts accounts by push-permission state.
func (s *AdminNotificationService) Reach(ctx context.Context) (*NotifReach, error) {
	p, err := s.store.PushReach(ctx)
	if err != nil {
		return nil, fmt.Errorf("AdminNotificationService.Reach: %w", err)
	}
	out := &NotifReach{
		FCMConfigured: s.push.Configured(), Users: p.Users, Deliverable: p.Granted + p.Unknown,
		Granted: p.Granted, Unknown: p.Unknown, Denied: p.Denied, NotDetermined: p.NotDetermined, None: p.None,
	}
	for _, d := range p.Devices {
		out.Devices = append(out.Devices, struct {
			Platform   string `json:"platform"`
			Permission string `json:"permission"`
			Count      int    `json:"count"`
		}{d.Platform, d.Permission, d.Count})
	}
	return out, nil
}

// PushStateOf reduces a user's devices to one state: granted, unknown, denied,
// not_determined, or none when no device is registered.
func PushStateOf(devices []repository.PushDevice) string {
	has := map[string]bool{}
	for _, d := range devices {
		has[d.Permission] = true
	}
	switch {
	case len(devices) == 0:
		return "none"
	case has[repository.PermGranted]:
		return repository.PermGranted
	case has[repository.PermUnknown]:
		return repository.PermUnknown
	case has[repository.PermDenied]:
		return repository.PermDenied
	}
	return repository.PermNotDetermined
}

// InboxService serves a signed-in player's admin in-app messages.
type InboxService struct {
	repo inboxStore
}

type inboxStore interface {
	ListUnread(ctx context.Context, userID string) ([]repository.InboxMessage, error)
	MarkRead(ctx context.Context, userID, id string) (bool, error)
}

func NewInboxService(repo inboxStore) *InboxService { return &InboxService{repo: repo} }

// Unread lists the player's unread messages, newest first.
func (s *InboxService) Unread(ctx context.Context, userID string) ([]repository.InboxMessage, error) {
	return s.repo.ListUnread(ctx, userID)
}

// MarkRead marks one message read. Unknown ids and other players' messages are
// a silent no-op so the call stays idempotent.
func (s *InboxService) MarkRead(ctx context.Context, userID, id string) error {
	if !uuidRe.MatchString(id) {
		return nil
	}
	_, err := s.repo.MarkRead(ctx, userID, id)
	return err
}
