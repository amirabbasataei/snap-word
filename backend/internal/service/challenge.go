package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"

	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/ws"
)

var (
	ErrNotFriends        = errors.New("users are not friends")
	ErrChallengeNotFound = errors.New("challenge not found")
	ErrChallengeExpired  = errors.New("challenge has expired")
	ErrNotChallenged     = errors.New("you are not the challenged player")
)

// ChallengeService manages friend challenge creation and responses.
type ChallengeService struct {
	challengeRepo *repository.ChallengeRepository
	friendRepo    *repository.FriendshipRepository
	userRepo      *repository.UserRepository
	hub           *ws.Hub
	notifSvc      *NotificationService
}

func NewChallengeService(
	challengeRepo *repository.ChallengeRepository,
	friendRepo *repository.FriendshipRepository,
	userRepo *repository.UserRepository,
	hub *ws.Hub,
	notifSvc *NotificationService,
) *ChallengeService {
	return &ChallengeService{
		challengeRepo: challengeRepo,
		friendRepo:    friendRepo,
		userRepo:      userRepo,
		hub:           hub,
		notifSvc:      notifSvc,
	}
}

// CreateChallenge validates that the two users are friends, then creates a pending challenge.
func (s *ChallengeService) CreateChallenge(ctx context.Context, challengerID, challengedID, mode string) (*repository.FriendChallenge, error) {
	if mode != "classic" && mode != "time_attack" {
		return nil, fmt.Errorf("invalid mode: %s", mode)
	}

	friendship, err := s.friendRepo.GetFriendship(ctx, challengerID, challengedID)
	if err != nil || friendship.Status != "accepted" {
		return nil, ErrNotFriends
	}

	ch, err := s.challengeRepo.CreateChallenge(ctx, challengerID, challengedID, mode)
	if err != nil {
		return nil, fmt.Errorf("CreateChallenge: %w", err)
	}

	challenger, _ := s.userRepo.GetUserByID(ctx, challengerID)
	challengerName := challengerID
	if challenger != nil {
		challengerName = challenger.Username
	}

	modeName := "Classic"
	if mode == "time_attack" {
		modeName = "Time Attack"
	}

	if err := s.notifSvc.SendToUser(ctx, challengedID,
		"Friend challenge received",
		fmt.Sprintf("%s challenged you to a %s match!", challengerName, modeName),
	); err != nil {
		slog.Warn("CreateChallenge: notification failed", "challengedID", challengedID, "error", err)
	}

	return ch, nil
}

// RespondToChallenge accepts or declines a pending challenge.
// On accept: creates a private WS room and returns the room ID.
// On decline: notifies the challenger.
func (s *ChallengeService) RespondToChallenge(ctx context.Context, challengeID, responderID, action string) (roomID string, err error) {
	if action != "accept" && action != "decline" {
		return "", fmt.Errorf("invalid action: %s", action)
	}

	ch, err := s.challengeRepo.GetChallenge(ctx, challengeID)
	if err != nil {
		if errors.Is(err, repository.ErrChallengeNotFound) {
			return "", ErrChallengeNotFound
		}
		return "", fmt.Errorf("RespondToChallenge get: %w", err)
	}

	if ch.ChallengedID != responderID {
		return "", ErrNotChallenged
	}
	if ch.Status != "pending" {
		return "", ErrChallengeExpired
	}

	responder, _ := s.userRepo.GetUserByID(ctx, responderID)
	responderName := responderID
	if responder != nil {
		responderName = responder.Username
	}

	if action == "decline" {
		if err := s.challengeRepo.RespondToChallenge(ctx, challengeID, "declined", nil); err != nil {
			return "", fmt.Errorf("RespondToChallenge decline: %w", err)
		}
		if err := s.notifSvc.SendToUser(ctx, ch.ChallengerID,
			"Friend challenge declined",
			fmt.Sprintf("%s declined your challenge.", responderName),
		); err != nil {
			slog.Warn("RespondToChallenge: decline notification failed", "challengerID", ch.ChallengerID, "error", err)
		}
		return "", nil
	}

	// Accept: create a private room and record the room ID.
	roomID = newChallengeRoomID()
	s.hub.GetOrCreateRoom(roomID, ch.Mode)

	if err := s.challengeRepo.RespondToChallenge(ctx, challengeID, "accepted", &roomID); err != nil {
		return "", fmt.Errorf("RespondToChallenge accept: %w", err)
	}

	if err := s.notifSvc.SendToUser(ctx, ch.ChallengerID,
		"Friend challenge accepted",
		fmt.Sprintf("%s accepted your challenge! Room: %s", responderName, roomID),
	); err != nil {
		slog.Warn("RespondToChallenge: accept notification failed", "challengerID", ch.ChallengerID, "error", err)
	}

	return roomID, nil
}

// GetPendingChallenges returns non-expired pending challenges for the given user.
func (s *ChallengeService) GetPendingChallenges(ctx context.Context, userID string) ([]*repository.FriendChallenge, error) {
	return s.challengeRepo.GetPendingChallenges(ctx, userID)
}

// ExpireOldChallenges marks overdue challenges as expired and notifies challengers.
// Called by the scheduler every 5 minutes.
func (s *ChallengeService) ExpireOldChallenges(ctx context.Context) {
	expired, err := s.challengeRepo.ExpireOldChallenges(ctx)
	if err != nil {
		slog.Error("ExpireOldChallenges: query failed", "error", err)
		return
	}
	for _, ch := range expired {
		challenged, _ := s.userRepo.GetUserByID(ctx, ch.ChallengedID)
		challengedName := ch.ChallengedID
		if challenged != nil {
			challengedName = challenged.Username
		}
		if err := s.notifSvc.SendToUser(ctx, ch.ChallengerID,
			"Friend challenge expired",
			fmt.Sprintf("Your challenge to %s has expired.", challengedName),
		); err != nil {
			slog.Warn("ExpireOldChallenges: notification failed",
				"challengerID", ch.ChallengerID, "error", err)
		}
	}
	if len(expired) > 0 {
		slog.Info("scheduler: expired friend challenges", "count", len(expired))
	}
}

func newChallengeRoomID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%x", b)
}
