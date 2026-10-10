// Package testutil holds in-memory fakes shared by tests of the admin stack.
package testutil

import (
	"context"
	"sync"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/repository"
)

// NewRedis starts an in-memory Redis for the test and returns it with a client.
func NewRedis(t interface {
	Helper()
	Cleanup(func())
	Fatalf(string, ...any)
}) (*miniredis.Miniredis, *redis.Client) {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { rdb.Close(); mr.Close() })
	return mr, rdb
}

// FakeAdminStore is an in-memory admin_users + admin_audit_log.
type FakeAdminStore struct {
	mu     sync.Mutex
	users  map[string]*repository.AdminUser // by id
	next   int
	Audits []repository.AuditEntry
}

func NewFakeAdminStore() *FakeAdminStore {
	return &FakeAdminStore{users: map[string]*repository.AdminUser{}}
}

func (f *FakeAdminStore) find(pred func(*repository.AdminUser) bool) *repository.AdminUser {
	for _, u := range f.users {
		if pred(u) {
			cp := *u
			return &cp
		}
	}
	return nil
}

func (f *FakeAdminStore) GetByUsername(_ context.Context, username string) (*repository.AdminUser, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if u := f.find(func(u *repository.AdminUser) bool { return u.Username == username }); u != nil {
		return u, nil
	}
	return nil, repository.ErrAdminNotFound
}

func (f *FakeAdminStore) GetByID(_ context.Context, id string) (*repository.AdminUser, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if u, ok := f.users[id]; ok {
		cp := *u
		return &cp, nil
	}
	return nil, repository.ErrAdminNotFound
}

func (f *FakeAdminStore) Create(_ context.Context, username, hash, role string) (*repository.AdminUser, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.find(func(u *repository.AdminUser) bool { return u.Username == username }) != nil {
		return nil, repository.ErrAdminUsernameTaken
	}
	f.next++
	u := &repository.AdminUser{ID: "admin-" + string(rune('0'+f.next)), Username: username, PasswordHash: hash, Role: role, CreatedAt: time.Now()}
	f.users[u.ID] = u
	cp := *u
	return &cp, nil
}

func (f *FakeAdminStore) mutate(id string, fn func(*repository.AdminUser)) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	u, ok := f.users[id]
	if !ok {
		return repository.ErrAdminNotFound
	}
	fn(u)
	return nil
}

func (f *FakeAdminStore) SetPassword(_ context.Context, id, hash string) error {
	return f.mutate(id, func(u *repository.AdminUser) { u.PasswordHash = hash })
}

func (f *FakeAdminStore) SetDisabled(_ context.Context, id string, disabled bool) error {
	return f.mutate(id, func(u *repository.AdminUser) {
		if disabled {
			now := time.Now()
			u.DisabledAt = &now
		} else {
			u.DisabledAt = nil
		}
	})
}

// SetRole changes a role directly (the service has no role-change API until A7).
func (f *FakeAdminStore) SetRole(id, role string) {
	_ = f.mutate(id, func(u *repository.AdminUser) { u.Role = role })
}

func (f *FakeAdminStore) TouchLogin(_ context.Context, id string) error {
	return f.mutate(id, func(u *repository.AdminUser) { now := time.Now(); u.LastLoginAt = &now })
}

func (f *FakeAdminStore) CountActive(_ context.Context) (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, u := range f.users {
		if u.DisabledAt == nil {
			n++
		}
	}
	return n, nil
}

func (f *FakeAdminStore) InsertAudit(_ context.Context, e repository.AuditEntry) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Audits = append(f.Audits, e)
	return nil
}

// AuditActions lists the recorded audit actions in order.
func (f *FakeAdminStore) AuditActions() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]string, len(f.Audits))
	for i, a := range f.Audits {
		out[i] = a.Action
	}
	return out
}
