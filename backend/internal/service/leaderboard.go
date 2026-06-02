package service

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

const weeklyLeaderboardKey = "leaderboard:global:weekly"

// LeaderboardEntry is one row in a leaderboard response.
type LeaderboardEntry struct {
	Rank     int     `json:"rank"`
	UserID   string  `json:"user_id"`
	Username string  `json:"username"`
	Score    float64 `json:"score"`
}

// LeaderboardService manages the Redis weekly sorted set and weekly reset logic.
type LeaderboardService struct {
	rdb        *redis.Client
	userRepo   *repository.UserRepository
	friendRepo *repository.FriendshipRepository
	lbRepo     *repository.LeaderboardRepository
	notifSvc   *NotificationService
}

func NewLeaderboardService(
	rdb *redis.Client,
	userRepo *repository.UserRepository,
	friendRepo *repository.FriendshipRepository,
	lbRepo *repository.LeaderboardRepository,
	notifSvc *NotificationService,
) *LeaderboardService {
	return &LeaderboardService{
		rdb:        rdb,
		userRepo:   userRepo,
		friendRepo: friendRepo,
		lbRepo:     lbRepo,
		notifSvc:   notifSvc,
	}
}

// AddScore increments a player's score in the weekly sorted set.
// Call only for multiplayer and Daily Challenge games — not solo.
func (s *LeaderboardService) AddScore(ctx context.Context, userID string, score int) error {
	if err := s.rdb.ZIncrBy(ctx, weeklyLeaderboardKey, float64(score), userID).Err(); err != nil {
		return fmt.Errorf("leaderboard.AddScore: %w", err)
	}
	return nil
}

// GetTopN returns the top n players by weekly score, with usernames resolved from DB.
func (s *LeaderboardService) GetTopN(ctx context.Context, n int) ([]LeaderboardEntry, error) {
	members, err := s.rdb.ZRevRangeWithScores(ctx, weeklyLeaderboardKey, 0, int64(n-1)).Result()
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN: %w", err)
	}
	if len(members) == 0 {
		return []LeaderboardEntry{}, nil
	}

	userIDs := make([]string, len(members))
	for i, m := range members {
		userIDs[i] = m.Member.(string)
	}

	usernames, err := s.userRepo.GetUsernames(ctx, userIDs)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN usernames: %w", err)
	}

	entries := make([]LeaderboardEntry, len(members))
	for i, m := range members {
		uid := m.Member.(string)
		entries[i] = LeaderboardEntry{
			Rank:     i + 1,
			UserID:   uid,
			Username: usernames[uid],
			Score:    m.Score,
		}
	}
	return entries, nil
}

// GetPlayerRank returns the 1-indexed rank and score for userID.
// Returns 0, 0, nil if the player has no score this week.
func (s *LeaderboardService) GetPlayerRank(ctx context.Context, userID string) (rank int64, score float64, err error) {
	r, err := s.rdb.ZRevRank(ctx, weeklyLeaderboardKey, userID).Result()
	if err == redis.Nil {
		return 0, 0, nil
	}
	if err != nil {
		return 0, 0, fmt.Errorf("leaderboard.GetPlayerRank: %w", err)
	}
	sc, err := s.rdb.ZScore(ctx, weeklyLeaderboardKey, userID).Result()
	if err != nil {
		return 0, 0, fmt.Errorf("leaderboard.GetPlayerRank score: %w", err)
	}
	return r + 1, sc, nil // ZRevRank is 0-indexed
}

// GetFriendsLeaderboard returns a sorted leaderboard of the user's friends (plus themselves).
func (s *LeaderboardService) GetFriendsLeaderboard(ctx context.Context, userID string, limit int) ([]LeaderboardEntry, error) {
	friendIDs, err := s.friendRepo.GetFriendIDs(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetFriendsLeaderboard: %w", err)
	}

	// Include the requesting user.
	candidates := append(friendIDs, userID)

	type candidate struct {
		userID string
		score  float64
	}
	var ranked []candidate

	for _, uid := range candidates {
		sc, err := s.rdb.ZScore(ctx, weeklyLeaderboardKey, uid).Result()
		if err == redis.Nil {
			sc = 0
		} else if err != nil {
			slog.Warn("leaderboard: ZScore failed", "userID", uid, "error", err)
			sc = 0
		}
		ranked = append(ranked, candidate{uid, sc})
	}

	sort.Slice(ranked, func(i, j int) bool {
		return ranked[i].score > ranked[j].score
	})
	if len(ranked) > limit {
		ranked = ranked[:limit]
	}

	allIDs := make([]string, len(ranked))
	for i, c := range ranked {
		allIDs[i] = c.userID
	}
	usernames, err := s.userRepo.GetUsernames(ctx, allIDs)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetFriendsLeaderboard usernames: %w", err)
	}

	entries := make([]LeaderboardEntry, len(ranked))
	for i, c := range ranked {
		entries[i] = LeaderboardEntry{
			Rank:     i + 1,
			UserID:   c.userID,
			Username: usernames[c.userID],
			Score:    c.score,
		}
	}
	return entries, nil
}

// RunWeeklyReset is called by the scheduler on Sunday 00:00 UTC.
// It rewards the top 3 players, records the rewards, and clears the Redis key.
func (s *LeaderboardService) RunWeeklyReset(ctx context.Context, weekStart time.Time) {
	slog.Info("leaderboard: weekly reset starting", "weekStart", weekStart)

	top3, err := s.GetTopN(ctx, 3)
	if err != nil {
		slog.Error("weekly reset: GetTopN failed", "error", err)
		return
	}

	rewardCoins := []int{config.CoinWeeklyRank1, config.CoinWeeklyRank2, config.CoinWeeklyRank3}

	for i, entry := range top3 {
		if i >= len(rewardCoins) {
			break
		}
		coins := rewardCoins[i]

		inserted, err := s.lbRepo.InsertWeeklyReward(ctx, weekStart, entry.UserID, entry.Rank, coins)
		if err != nil {
			slog.Error("weekly reset: InsertWeeklyReward failed", "userID", entry.UserID, "error", err)
			continue
		}
		if !inserted {
			// Already rewarded this week (idempotent re-run).
			continue
		}

		if err := s.userRepo.AwardCoins(ctx, entry.UserID, coins); err != nil {
			slog.Error("weekly reset: AwardCoins failed", "userID", entry.UserID, "error", err)
		}
		if err := s.notifSvc.SendToUser(ctx, entry.UserID,
			"Weekly Leaderboard Reward",
			fmt.Sprintf("You finished #%d and earned %d coins!", entry.Rank, coins),
		); err != nil {
			slog.Warn("weekly reset: notification failed", "userID", entry.UserID, "error", err)
		}
		slog.Info("weekly reset: rewarded", "userID", entry.UserID, "rank", entry.Rank, "coins", coins)
	}

	if err := s.rdb.Del(ctx, weeklyLeaderboardKey).Err(); err != nil {
		slog.Error("weekly reset: Del Redis key failed", "error", err)
	}
	slog.Info("leaderboard: weekly reset complete")
}
