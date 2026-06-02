package service

import (
	"context"
	"log/slog"
)

// NotificationService sends push notifications to users.
// Real FCM implementation arrives in Phase 12; this stub logs and returns nil.
type NotificationService struct{}

func NewNotificationService() *NotificationService {
	return &NotificationService{}
}

func (s *NotificationService) SendToUser(_ context.Context, userID, title, body string) error {
	slog.Info("notification.SendToUser (stub)", "userID", userID, "title", title, "body", body)
	return nil
}
