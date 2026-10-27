package handler_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/testutil"
)

type recordingStore struct{ batches []repository.AnalyticsBatch }

func (r *recordingStore) InsertAnalyticsEvents(_ context.Context, b repository.AnalyticsBatch) (int, error) {
	r.batches = append(r.batches, b)
	return len(b.Events), nil
}

type tokenStub struct{}

func (tokenStub) ParseAccessToken(tok string) (string, string, error) {
	if tok == "good" {
		return "user-42", "someone", nil
	}
	return "", "", errors.New("bad token")
}

func ingestRouter(t *testing.T) (*gin.Engine, *recordingStore) {
	t.Helper()
	_, rdb := testutil.NewRedis(t)
	store := &recordingStore{}
	h := handler.NewAnalyticsHandler(service.NewAnalyticsService(store, rdb), tokenStub{})
	r := gin.New()
	r.POST("/api/v1/analytics/events", h.Ingest)
	return r, store
}

func postEvents(r *gin.Engine, auth, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/analytics/events", bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func analyticsBody() string {
	return `{"install_id":"aaaaaaaa-0000-4000-8000-000000000001","platform":"ios","app_version":"1.0.0","user_id":"someone-else","events":[` +
		`{"client_event_id":"eeeeeeee-0000-4000-8000-000000000001","name":"app_open","ts":` + itoa(time.Now().UnixMilli()) + `}]}`
}

func itoa(n int64) string { b, _ := json.Marshal(n); return string(b) }

func TestAnalyticsIngest_GuestNeedsNoToken(t *testing.T) {
	r, store := ingestRouter(t)
	w := postEvents(r, "", analyticsBody())
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"accepted":1`) {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if store.batches[0].UserID != "" {
		t.Errorf("guest batch carried user %q", store.batches[0].UserID)
	}
}

func TestAnalyticsIngest_UserIDComesFromTokenNeverBody(t *testing.T) {
	r, store := ingestRouter(t)
	// The body above even names another user_id; it must be ignored.
	if w := postEvents(r, "Bearer good", analyticsBody()); w.Code != http.StatusOK {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if store.batches[0].UserID != "user-42" {
		t.Errorf("user = %q, want user-42", store.batches[0].UserID)
	}
	// A bad token downgrades to guest instead of failing the upload.
	if w := postEvents(r, "Bearer nope", strings.Replace(analyticsBody(), "000000000001\",\"name", "000000000009\",\"name", 1)); w.Code != http.StatusOK {
		t.Fatalf("bad token: %d %s", w.Code, w.Body)
	}
	if store.batches[1].UserID != "" {
		t.Errorf("bad token batch user = %q", store.batches[1].UserID)
	}
}

func TestAnalyticsIngest_Rejections(t *testing.T) {
	r, _ := ingestRouter(t)
	for name, body := range map[string]string{
		"not json":    `{`,
		"no install":  `{"events":[{"client_event_id":"x","name":"app_open","ts":1}]}`,
		"empty batch": `{"install_id":"aaaaaaaa-0000-4000-8000-000000000001","events":[]}`,
	} {
		if w := postEvents(r, "", body); w.Code != http.StatusBadRequest {
			t.Errorf("%s: %d %s", name, w.Code, w.Body)
		}
	}
	big := `{"install_id":"aaaaaaaa-0000-4000-8000-000000000001","events":[{"client_event_id":"x","name":"app_open","ts":1,"props":{"a":"` + strings.Repeat("x", 300<<10) + `"}}]}`
	if w := postEvents(r, "", big); w.Code != http.StatusBadRequest {
		t.Errorf("oversized body: %d", w.Code)
	}
}

func TestAnalyticsIngest_RateLimited(t *testing.T) {
	r, _ := ingestRouter(t)
	var last *httptest.ResponseRecorder
	for i := 0; i < 40; i++ {
		last = postEvents(r, "", analyticsBody())
	}
	if last.Code != http.StatusTooManyRequests {
		t.Fatalf("40 rapid requests ended with %d", last.Code)
	}
}
