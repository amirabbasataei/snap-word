package service

import (
	"context"
	"fmt"
	"log/slog"

	"wordchain/backend/internal/repository"
)

// AuditActor identifies who performed an admin action. AdminID is empty for
// the X-Admin-Key script (Name "script") and for failed logins (Name is the
// attempted username).
type AuditActor struct {
	AdminID string
	Name    string
	IP      string
}

// AuditTarget is the thing an action touched, e.g. {"taunt", "hurry_up"}.
type AuditTarget struct {
	Type string
	ID   string
}

type auditStore interface {
	InsertAudit(ctx context.Context, e repository.AuditEntry) error
}

// AuditService writes the admin audit trail.
type AuditService struct {
	store auditStore
}

func NewAuditService(store auditStore) *AuditService {
	return &AuditService{store: store}
}

// Record appends one audit row. The action it describes has usually already
// happened, so callers log the returned error rather than failing the request;
// LogRecord does exactly that.
func (s *AuditService) Record(ctx context.Context, actor AuditActor, action string, target AuditTarget, payload any) error {
	err := s.store.InsertAudit(ctx, repository.AuditEntry{
		AdminID:    actor.AdminID,
		Actor:      actor.Name,
		Action:     action,
		TargetType: target.Type,
		TargetID:   target.ID,
		Payload:    payload,
		IP:         actor.IP,
	})
	if err != nil {
		return fmt.Errorf("AuditService.Record %s: %w", action, err)
	}
	return nil
}

// LogRecord is Record that logs a failure instead of returning it.
func (s *AuditService) LogRecord(ctx context.Context, actor AuditActor, action string, target AuditTarget, payload any) {
	if err := s.Record(ctx, actor, action, target, payload); err != nil {
		slog.Error("admin audit write failed", "action", action, "actor", actor.Name, "error", err)
	}
}
