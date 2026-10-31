package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
)

// ---- player inbox ----

type fakeInbox struct {
	unread []repository.InboxMessage
	read   map[string]string // message id -> user id
}

func (f *fakeInbox) ListUnread(_ context.Context, userID string) ([]repository.InboxMessage, error) {
	if userID != "user-1" {
		return nil, nil
	}
	return f.unread, nil
}

func (f *fakeInbox) MarkRead(_ context.Context, userID, id string) (bool, error) {
	f.read[id] = userID
	return true, nil
}

func inboxRouter(f *fakeInbox) *gin.Engine {
	h := handler.NewInboxHandler(service.NewInboxService(f))
	r := gin.New()
	r.Use(func(c *gin.Context) { c.Set(middleware.ContextKeyUserID, "user-1") })
	r.GET("/api/v1/inbox", h.List)
	r.POST("/api/v1/inbox/:id/read", h.MarkRead)
	return r
}

func TestInbox_ListAndMarkRead(t *testing.T) {
	const id = "aaaaaaaa-0000-4000-8000-000000000001"
	f := &fakeInbox{read: map[string]string{}, unread: []repository.InboxMessage{
		{ID: id, Title: "سلام", Body: "متن", Route: "/daily", CreatedAt: time.Now()},
	}}
	r := inboxRouter(f)

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/inbox", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("list = %d: %s", w.Code, w.Body)
	}
	var out struct {
		Data struct {
			Messages []struct{ ID, Title, Body, Route string } `json:"messages"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil || len(out.Data.Messages) != 1 || out.Data.Messages[0].Route != "/daily" {
		t.Fatalf("list body = %s (%v)", w.Body, err)
	}

	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/api/v1/inbox/"+id+"/read", nil))
	if w.Code != http.StatusOK || f.read[id] != "user-1" {
		t.Fatalf("read = %d, marked %v", w.Code, f.read)
	}

	// A malformed id is a harmless no-op, not a database error.
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodPost, "/api/v1/inbox/not-a-uuid/read", nil))
	if w.Code != http.StatusOK || len(f.read) != 1 {
		t.Fatalf("bad id = %d, marked %v", w.Code, f.read)
	}
}

func TestRegisterToken_RejectsUnknownPermission(t *testing.T) {
	r := newNotificationRouter()
	w := postJSON(r, "/api/v1/notifications/token", map[string]string{
		"token": "t", "platform": "android", "permission": "maybe",
	})
	if w.Code != http.StatusBadRequest {
		t.Errorf("got %d, want 400", w.Code)
	}
}

// ---- admin notifications: error mapping ----

type noStore struct{}

func (noStore) CountAudience(context.Context, repository.NotifAudience, time.Time) (*repository.AudienceCounts, error) {
	return &repository.AudienceCounts{Recipients: 3, Granted: 1}, nil
}
func (noStore) PushTargets(context.Context, repository.NotifAudience, time.Time) ([]repository.DeviceToken, error) {
	return nil, nil
}
func (noStore) CreateCampaign(context.Context, repository.NotifCampaignInput, time.Time) (*repository.NotifCampaign, error) {
	return &repository.NotifCampaign{ID: "c"}, nil
}
func (noStore) FinishPush(context.Context, string, repository.PushOutcome) error { return nil }
func (noStore) ListCampaigns(context.Context, int, int) ([]repository.NotifCampaign, int, error) {
	return nil, 0, nil
}
func (noStore) GetCampaign(context.Context, string) (*repository.NotifCampaign, error) {
	return nil, repository.ErrCampaignNotFound
}
func (noStore) CampaignUsers(context.Context, string, []string) ([]repository.NotifUser, error) {
	return nil, nil
}
func (noStore) PushReach(context.Context) (*repository.PushReach, error) {
	return &repository.PushReach{}, nil
}
func (noStore) ExistingUserIDs(context.Context, []string) (map[string]bool, error) { return nil, nil }
func (noStore) InsertAudit(context.Context, repository.AuditEntry) error           { return nil }

type offPush struct{}

func (offPush) Configured() bool { return false }
func (offPush) SendBatch(context.Context, []service.PushTarget, string, string, string) service.PushResult {
	return service.PushResult{}
}

func adminNotifRouter() *gin.Engine {
	svc := service.NewAdminNotificationService(noStore{}, offPush{}, service.NewAuditService(noStore{}))
	h := handler.NewAdminNotificationsHandler(svc)
	r := gin.New()
	r.POST("/n/preview", h.Preview)
	r.POST("/n", h.Send)
	r.GET("/n/:id", h.Get)
	return r
}

func notifErrCode(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var e struct {
		Error struct{ Code string } `json:"error"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &e)
	return e.Error.Code
}

func TestAdminNotifications_ErrorMapping(t *testing.T) {
	r := adminNotifRouter()
	all := map[string]any{"type": "all"}
	cases := []struct {
		name   string
		path   string
		body   map[string]any
		status int
		code   string
	}{
		{"unknown audience", "/n/preview", map[string]any{"audience": map[string]any{"type": "nobody"}}, 400, "invalid_audience"},
		{"empty title", "/n", map[string]any{"title": "", "body": "b", "channels": []string{"inapp"}, "audience": all}, 400, "invalid_title"},
		{"no channels", "/n", map[string]any{"title": "t", "body": "b", "channels": []string{}, "audience": all}, 400, "invalid_channels"},
		{"bad route", "/n", map[string]any{"title": "t", "body": "b", "route": "/x", "channels": []string{"inapp"}, "audience": all}, 400, "invalid_route"},
		{"push while FCM is off", "/n", map[string]any{"title": "t", "body": "b", "channels": []string{"push"}, "audience": all}, 409, "fcm_not_configured"},
	}
	for _, c := range cases {
		w := postJSON(r, c.path, c.body)
		if w.Code != c.status || notifErrCode(t, w) != c.code {
			t.Errorf("%s: got %d %q, want %d %q (%s)", c.name, w.Code, notifErrCode(t, w), c.status, c.code, w.Body)
		}
	}

	// A valid in-app send goes through while push is off.
	w := postJSON(r, "/n", map[string]any{"title": "t", "body": "b", "channels": []string{"inapp"}, "audience": all})
	if w.Code != http.StatusOK {
		t.Errorf("in-app send = %d: %s", w.Code, w.Body)
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/n/eeeeeeee-0000-4000-8000-0000000000ff", nil))
	if w.Code != http.StatusNotFound || notifErrCode(t, w) != "not_found" {
		t.Errorf("missing campaign = %d %q", w.Code, notifErrCode(t, w))
	}
}
