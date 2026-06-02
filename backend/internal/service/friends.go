package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"wordchain/backend/internal/repository"
)

var (
	ErrSelfRequest          = errors.New("cannot send friend request to yourself")
	ErrFriendRequestExists  = errors.New("friend request already exists")
	ErrFriendRequestNotFound = errors.New("friend request not found")
)

// FriendService manages friend requests and the friends list.
type FriendService struct {
	friendRepo *repository.FriendshipRepository
	userRepo   *repository.UserRepository
	notifSvc   *NotificationService
}

func NewFriendService(
	friendRepo *repository.FriendshipRepository,
	userRepo *repository.UserRepository,
	notifSvc *NotificationService,
) *FriendService {
	return &FriendService{friendRepo: friendRepo, userRepo: userRepo, notifSvc: notifSvc}
}

// SendFriendRequest looks up targetUsername and sends a friend request.
// Returns ErrSelfRequest, ErrFriendRequestExists, or ErrUserNotFound on conflict.
func (s *FriendService) SendFriendRequest(ctx context.Context, requesterID, targetUsername string) (*repository.User, error) {
	target, err := s.userRepo.GetUserByUsername(ctx, targetUsername)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			return nil, repository.ErrUserNotFound
		}
		return nil, fmt.Errorf("SendFriendRequest lookup: %w", err)
	}

	if target.ID == requesterID {
		return nil, ErrSelfRequest
	}

	// Check if a reverse request already exists (they already sent one to us).
	existing, err := s.friendRepo.GetFriendship(ctx, requesterID, target.ID)
	if err == nil {
		// Any status (pending, accepted, declined) counts as an existing record.
		_ = existing
		return nil, ErrFriendRequestExists
	}
	if !errors.Is(err, repository.ErrFriendshipNotFound) {
		return nil, fmt.Errorf("SendFriendRequest check: %w", err)
	}

	if err := s.friendRepo.SendRequest(ctx, requesterID, target.ID); err != nil {
		if errors.Is(err, repository.ErrFriendshipExists) {
			return nil, ErrFriendRequestExists
		}
		return nil, fmt.Errorf("SendFriendRequest: %w", err)
	}

	requester, _ := s.userRepo.GetUserByID(ctx, requesterID)
	requesterName := requesterID
	if requester != nil {
		requesterName = requester.Username
	}

	if err := s.notifSvc.SendToUser(ctx, target.ID,
		"New friend request",
		fmt.Sprintf("%s wants to be your friend.", requesterName),
	); err != nil {
		slog.Warn("SendFriendRequest: notification failed", "target", target.ID, "error", err)
	}

	return target, nil
}

// RespondToFriendRequest accepts or declines a pending request from requesterID to addresseeID.
// action must be "accept" or "decline".
func (s *FriendService) RespondToFriendRequest(ctx context.Context, addresseeID, requesterID, action string) error {
	if action != "accept" && action != "decline" {
		return fmt.Errorf("invalid action: %s", action)
	}

	status := "accepted"
	if action == "decline" {
		status = "declined"
	}

	if err := s.friendRepo.RespondToRequest(ctx, requesterID, addresseeID, status); err != nil {
		if errors.Is(err, repository.ErrFriendshipNotFound) {
			return ErrFriendRequestNotFound
		}
		return fmt.Errorf("RespondToFriendRequest: %w", err)
	}

	if action == "accept" {
		addressee, _ := s.userRepo.GetUserByID(ctx, addresseeID)
		addresseeName := addresseeID
		if addressee != nil {
			addresseeName = addressee.Username
		}
		if err := s.notifSvc.SendToUser(ctx, requesterID,
			"Friend request accepted",
			fmt.Sprintf("%s accepted your friend request.", addresseeName),
		); err != nil {
			slog.Warn("RespondToFriendRequest: notification failed", "requesterID", requesterID, "error", err)
		}
	}

	return nil
}

// ListFriends returns the accepted friends list for userID with usernames.
func (s *FriendService) ListFriends(ctx context.Context, userID string) ([]*repository.FriendInfo, error) {
	friends, err := s.friendRepo.ListFriends(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("ListFriends: %w", err)
	}
	return friends, nil
}

// ListPendingRequests returns pending friend requests addressed to userID.
func (s *FriendService) ListPendingRequests(ctx context.Context, userID string) ([]*repository.PendingRequest, error) {
	reqs, err := s.friendRepo.ListPendingRequests(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("ListPendingRequests: %w", err)
	}
	return reqs, nil
}

// RemoveFriend removes the friendship between userID and friendID.
func (s *FriendService) RemoveFriend(ctx context.Context, userID, friendID string) error {
	if err := s.friendRepo.RemoveFriend(ctx, userID, friendID); err != nil {
		return fmt.Errorf("RemoveFriend: %w", err)
	}
	return nil
}
