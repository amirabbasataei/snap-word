package service

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/config"
	"wordchain/backend/internal/repository"
)

// Weekly board (Phase 25 S2): the net rating change («جام») of each player's
// rated games this week, plus their wins (tie-break) and rated games (prize
// eligibility). All three keys are cleared by the Saturday reset.
const (
	weeklyRatingKey = "leaderboard:weekly:rating" // zset userID → net Δ this week
	weeklyWinsKey   = "leaderboard:weekly:wins"   // hash userID → rated wins this week
	weeklyGamesKey  = "leaderboard:weekly:games"  // hash userID → rated games this week
	// legacyWeeklyKey held raw word points before S2. Nothing writes it any
	// more; the next weekly reset deletes it unpaid (deploy right after a reset).
	legacyWeeklyKey = "leaderboard:global:weekly"
)

// bannedFetchMargin is how many extra weekly rows GetTopN reads so that banned
// players dropped from the board do not leave it short.
const bannedFetchMargin = 20

// LeaderboardEntry is one row in a leaderboard response. Score is the weekly
// net rating change on the weekly board and the rating on the all-time and
// friends boards; Games is the rated games that board counts (this week / ever).
type LeaderboardEntry struct {
	Rank     int     `json:"rank"`
	UserID   string  `json:"user_id"`
	Username string  `json:"username"`
	Score    float64 `json:"score"`
	Games    int     `json:"games"`
	// Wins is set on the weekly board only (rated wins this week).
	Wins *int `json:"wins,omitempty"`
	// AvatarID is the player's premium avatar; empty for free/lapsed players.
	AvatarID string `json:"avatar_id,omitempty"`
}

// PlayerStanding is the requesting player's own row on a board. Rank is 0 when
// they are not on it (no rated game this week / too few rated games ever).
type PlayerStanding struct {
	Rank  int64
	Score float64
	Games int
	Wins  int // weekly board only
}

// LeaderboardService manages the weekly Redis board, the rating boards and the
// weekly reset.
type LeaderboardService struct {
	rdb        *redis.Client
	userRepo   *repository.UserRepository
	friendRepo *repository.FriendshipRepository
	lbRepo     *repository.LeaderboardRepository
	ratingRepo *repository.RatingRepository
	notifSvc   *NotificationService
}

func NewLeaderboardService(
	rdb *redis.Client,
	userRepo *repository.UserRepository,
	friendRepo *repository.FriendshipRepository,
	lbRepo *repository.LeaderboardRepository,
	ratingRepo *repository.RatingRepository,
	notifSvc *NotificationService,
) *LeaderboardService {
	return &LeaderboardService{
		rdb:        rdb,
		userRepo:   userRepo,
		friendRepo: friendRepo,
		lbRepo:     lbRepo,
		ratingRepo: ratingRepo,
		notifSvc:   notifSvc,
	}
}

// AddTotalScore adds a game's word points to the player's lifetime total
// (player_stats.total_score, a profile stat since S2 — it no longer ranks).
func (s *LeaderboardService) AddTotalScore(ctx context.Context, userID string, score int) error {
	if err := s.lbRepo.AddTotalScore(ctx, userID, score); err != nil {
		return fmt.Errorf("leaderboard.AddTotalScore: %w", err)
	}
	return nil
}

// RecordRatedGame adds one newly rated match to this week's board.
func (s *LeaderboardService) RecordRatedGame(ctx context.Context, winnerID, loserID string, winnerDelta, loserDelta int) error {
	pipe := s.rdb.TxPipeline()
	pipe.ZIncrBy(ctx, weeklyRatingKey, float64(winnerDelta), winnerID)
	pipe.ZIncrBy(ctx, weeklyRatingKey, float64(loserDelta), loserID)
	pipe.HIncrBy(ctx, weeklyWinsKey, winnerID, 1)
	pipe.HIncrBy(ctx, weeklyGamesKey, winnerID, 1)
	pipe.HIncrBy(ctx, weeklyGamesKey, loserID, 1)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("leaderboard.RecordRatedGame: %w", err)
	}
	return nil
}

// attachAvatars fills AvatarID from active premium perks. A lookup failure only
// costs the avatars, never the board, so it is logged and swallowed.
func (s *LeaderboardService) attachAvatars(ctx context.Context, entries []LeaderboardEntry) {
	ids := make([]string, len(entries))
	for i, e := range entries {
		ids[i] = e.UserID
	}
	perks, err := s.userRepo.GetPerks(ctx, ids)
	if err != nil {
		slog.Warn("leaderboard: GetPerks failed", "error", err)
		return
	}
	for i := range entries {
		entries[i].AvatarID = perks[entries[i].UserID].AvatarID
	}
}

// GetAvatarID returns the user's active premium avatar ("" when none).
func (s *LeaderboardService) GetAvatarID(ctx context.Context, userID string) string {
	perks, err := s.userRepo.GetPerks(ctx, []string{userID})
	if err != nil {
		slog.Warn("leaderboard: GetPerks failed", "userID", userID, "error", err)
		return ""
	}
	return perks[userID].AvatarID
}

// ---- all-time (rating) ----

// GetAllTimeTop returns the top n players by rating, among players with at
// least config.RatingMinGamesForBoard rated games.
func (s *LeaderboardService) GetAllTimeTop(ctx context.Context, n int) ([]LeaderboardEntry, error) {
	rows, err := s.ratingRepo.TopRated(ctx, n, config.RatingMinGamesForBoard, config.SystemAIUserID)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetAllTimeTop: %w", err)
	}
	entries := make([]LeaderboardEntry, len(rows))
	for i, r := range rows {
		entries[i] = LeaderboardEntry{Rank: i + 1, UserID: r.UserID, Username: r.Username,
			Score: float64(r.Rating), Games: r.RatedGames}
	}
	s.attachAvatars(ctx, entries)
	return entries, nil
}

// AllTimeStanding is the player's own all-time row: their rating and rated
// games always, their rank only once they qualify for the board.
func (s *LeaderboardService) AllTimeStanding(ctx context.Context, userID string) (PlayerStanding, error) {
	rank, row, err := s.ratingRepo.RatedRank(ctx, userID, config.RatingMinGamesForBoard, config.SystemAIUserID)
	if err != nil {
		return PlayerStanding{Score: config.RatingStart}, fmt.Errorf("leaderboard.AllTimeStanding: %w", err)
	}
	st := PlayerStanding{Rank: rank, Score: float64(row.Rating), Games: row.RatedGames}
	if row.Rating == 0 && row.RatedGames == 0 && row.Peak == 0 {
		st.Score = config.RatingStart // no player_stats row yet
	}
	return st, nil
}

// ---- weekly ----

type weeklyMember struct {
	id    string
	score float64
	wins  int
	games int
}

// weeklyLess orders the weekly board: net Δ, then wins, then user id.
func weeklyLess(a, b weeklyMember) bool {
	if a.score != b.score {
		return a.score > b.score
	}
	if a.wins != b.wins {
		return a.wins > b.wins
	}
	return a.id < b.id
}

func hashInts(vals []any) []int {
	out := make([]int, len(vals))
	for i, v := range vals {
		if s, ok := v.(string); ok {
			out[i], _ = strconv.Atoi(s)
		}
	}
	return out
}

// weeklyStats loads wins and games for the given members.
func (s *LeaderboardService) weeklyStats(ctx context.Context, members []weeklyMember) error {
	if len(members) == 0 {
		return nil
	}
	ids := make([]string, len(members))
	for i, m := range members {
		ids[i] = m.id
	}
	wins, err := s.rdb.HMGet(ctx, weeklyWinsKey, ids...).Result()
	if err != nil {
		return fmt.Errorf("weekly wins: %w", err)
	}
	games, err := s.rdb.HMGet(ctx, weeklyGamesKey, ids...).Result()
	if err != nil {
		return fmt.Errorf("weekly games: %w", err)
	}
	w, g := hashInts(wins), hashInts(games)
	for i := range members {
		members[i].wins, members[i].games = w[i], g[i]
	}
	return nil
}

func scoreArg(f float64) string { return strconv.FormatFloat(f, 'f', -1, 64) }

// GetTopN returns the top n players of this week's rating board, with
// usernames resolved from DB. Banned players are dropped.
func (s *LeaderboardService) GetTopN(ctx context.Context, n int) ([]LeaderboardEntry, error) {
	// Banned players stay in Redis (so an unban restores their week) and are
	// dropped on read; over-fetch so the board can still fill up.
	zs, err := s.rdb.ZRevRangeWithScores(ctx, weeklyRatingKey, 0, int64(n-1+bannedFetchMargin)).Result()
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN: %w", err)
	}
	if len(zs) == 0 {
		return []LeaderboardEntry{}, nil
	}
	seen := make(map[string]bool, len(zs))
	members := make([]weeklyMember, 0, len(zs))
	for _, z := range zs {
		id := z.Member.(string)
		seen[id] = true
		members = append(members, weeklyMember{id: id, score: z.Score})
	}
	// The wins tie-break must see every member tied with the last fetched one,
	// or a tied player with more wins just past the cut would be left out.
	if len(zs) == n+bannedFetchMargin {
		last := scoreArg(zs[len(zs)-1].Score)
		ties, err := s.rdb.ZRangeByScoreWithScores(ctx, weeklyRatingKey, &redis.ZRangeBy{Min: last, Max: last}).Result()
		if err != nil {
			return nil, fmt.Errorf("leaderboard.GetTopN ties: %w", err)
		}
		for _, z := range ties {
			if id := z.Member.(string); !seen[id] {
				seen[id] = true
				members = append(members, weeklyMember{id: id, score: z.Score})
			}
		}
	}

	ids := make([]string, len(members))
	for i, m := range members {
		ids[i] = m.id
	}
	banned, err := s.userRepo.BannedIDs(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN banned: %w", err)
	}
	kept := members[:0]
	for _, m := range members {
		if _, isBanned := banned[m.id]; !isBanned {
			kept = append(kept, m)
		}
	}
	members = kept
	if err := s.weeklyStats(ctx, members); err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN: %w", err)
	}
	sort.Slice(members, func(i, j int) bool { return weeklyLess(members[i], members[j]) })
	if len(members) > n {
		members = members[:n]
	}
	if len(members) == 0 {
		return []LeaderboardEntry{}, nil
	}

	ids = ids[:0]
	for _, m := range members {
		ids = append(ids, m.id)
	}
	usernames, err := s.userRepo.GetUsernames(ctx, ids)
	if err != nil {
		return nil, fmt.Errorf("leaderboard.GetTopN usernames: %w", err)
	}
	entries := make([]LeaderboardEntry, len(members))
	for i, m := range members {
		wins := m.wins
		entries[i] = LeaderboardEntry{Rank: i + 1, UserID: m.id, Username: usernames[m.id],
			Score: m.score, Games: m.games, Wins: &wins}
	}
	s.attachAvatars(ctx, entries)
	return entries, nil
}

// WeeklyStanding returns the player's rank (same order as GetTopN), net Δ,
// wins and rated games this week. All zero when they have no rated game yet.
func (s *LeaderboardService) WeeklyStanding(ctx context.Context, userID string) (PlayerStanding, error) {
	sc, err := s.rdb.ZScore(ctx, weeklyRatingKey, userID).Result()
	if err == redis.Nil {
		return PlayerStanding{}, nil
	}
	if err != nil {
		return PlayerStanding{}, fmt.Errorf("leaderboard.WeeklyStanding: %w", err)
	}
	me := []weeklyMember{{id: userID, score: sc}}
	if err := s.weeklyStats(ctx, me); err != nil {
		return PlayerStanding{}, fmt.Errorf("leaderboard.WeeklyStanding: %w", err)
	}
	above, err := s.rdb.ZCount(ctx, weeklyRatingKey, "("+scoreArg(sc), "+inf").Result()
	if err != nil {
		return PlayerStanding{}, fmt.Errorf("leaderboard.WeeklyStanding count: %w", err)
	}
	tied, err := s.rdb.ZRangeByScore(ctx, weeklyRatingKey, &redis.ZRangeBy{Min: scoreArg(sc), Max: scoreArg(sc)}).Result()
	if err != nil {
		return PlayerStanding{}, fmt.Errorf("leaderboard.WeeklyStanding ties: %w", err)
	}
	ties := make([]weeklyMember, 0, len(tied))
	for _, id := range tied {
		if id != userID {
			ties = append(ties, weeklyMember{id: id, score: sc})
		}
	}
	if err := s.weeklyStats(ctx, ties); err != nil {
		return PlayerStanding{}, fmt.Errorf("leaderboard.WeeklyStanding: %w", err)
	}
	for _, t := range ties {
		if weeklyLess(t, me[0]) {
			above++
		}
	}
	return PlayerStanding{Rank: above + 1, Score: sc, Wins: me[0].wins, Games: me[0].games}, nil
}

// ---- friends (rating) ----

// GetFriendsLeaderboard ranks the user and their (non-banned) friends by
// rating, and returns the user's own place in that list.
func (s *LeaderboardService) GetFriendsLeaderboard(ctx context.Context, userID string, limit int) ([]LeaderboardEntry, PlayerStanding, error) {
	friendIDs, err := s.friendRepo.GetFriendIDs(ctx, userID)
	if err != nil {
		return nil, PlayerStanding{}, fmt.Errorf("leaderboard.GetFriendsLeaderboard: %w", err)
	}
	banned, err := s.userRepo.BannedIDs(ctx, friendIDs)
	if err != nil {
		return nil, PlayerStanding{}, fmt.Errorf("leaderboard.GetFriendsLeaderboard banned: %w", err)
	}
	candidates := []string{userID}
	for _, id := range friendIDs {
		if _, isBanned := banned[id]; !isBanned && id != userID {
			candidates = append(candidates, id)
		}
	}
	ratings, err := s.ratingRepo.GetRatings(ctx, candidates)
	if err != nil {
		return nil, PlayerStanding{}, fmt.Errorf("leaderboard.GetFriendsLeaderboard ratings: %w", err)
	}
	ranked := make([]repository.RatingRow, len(candidates))
	for i, id := range candidates {
		r, ok := ratings[id]
		if !ok {
			r = repository.RatingRow{UserID: id, Rating: config.RatingStart, Peak: config.RatingStart}
		}
		ranked[i] = r
	}
	sort.Slice(ranked, func(i, j int) bool {
		a, b := ranked[i], ranked[j]
		if a.Rating != b.Rating {
			return a.Rating > b.Rating
		}
		if a.RatedGames != b.RatedGames {
			return a.RatedGames > b.RatedGames
		}
		return a.UserID < b.UserID
	})
	var me PlayerStanding
	for i, r := range ranked {
		if r.UserID == userID {
			me = PlayerStanding{Rank: int64(i + 1), Score: float64(r.Rating), Games: r.RatedGames}
			break
		}
	}
	if len(ranked) > limit {
		ranked = ranked[:limit]
	}

	ids := make([]string, len(ranked))
	for i, r := range ranked {
		ids[i] = r.UserID
	}
	usernames, err := s.userRepo.GetUsernames(ctx, ids)
	if err != nil {
		return nil, PlayerStanding{}, fmt.Errorf("leaderboard.GetFriendsLeaderboard usernames: %w", err)
	}
	entries := make([]LeaderboardEntry, len(ranked))
	for i, r := range ranked {
		entries[i] = LeaderboardEntry{Rank: i + 1, UserID: r.UserID, Username: usernames[r.UserID],
			Score: float64(r.Rating), Games: r.RatedGames}
	}
	s.attachAvatars(ctx, entries)
	return entries, me, nil
}

// ---- weekly reset ----

// WeeklyPrizeWinners picks up to n prize winners from the weekly board (in
// board order): only players with a positive net Δ and at least
// config.WeeklyMinRatedGames rated games qualify. Rank is the prize place.
func WeeklyPrizeWinners(board []LeaderboardEntry, n int) []LeaderboardEntry {
	var out []LeaderboardEntry
	for _, e := range board {
		if len(out) == n {
			break
		}
		if e.Score <= 0 || e.Games < config.WeeklyMinRatedGames {
			continue
		}
		e.Rank = len(out) + 1
		out = append(out, e)
	}
	return out
}

// RunWeeklyReset is called by the scheduler on Saturday 00:00 Iran time (end of Friday).
// It rewards the top 3 eligible players, records the rewards, and clears the week.
func (s *LeaderboardService) RunWeeklyReset(ctx context.Context, weekStart time.Time) {
	slog.Info("leaderboard: weekly reset starting", "weekStart", weekStart)

	board, err := s.GetTopN(ctx, config.WeeklyPrizeScanLimit)
	if err != nil {
		slog.Error("weekly reset: GetTopN failed", "error", err)
		return
	}

	rewardCoins := []int{config.CoinWeeklyRank1, config.CoinWeeklyRank2, config.CoinWeeklyRank3}
	for _, entry := range WeeklyPrizeWinners(board, len(rewardCoins)) {
		coins := rewardCoins[entry.Rank-1]

		inserted, err := s.lbRepo.InsertWeeklyReward(ctx, weekStart, entry.UserID, entry.Rank, coins)
		if err != nil {
			slog.Error("weekly reset: InsertWeeklyReward failed", "userID", entry.UserID, "error", err)
			continue
		}
		if !inserted {
			// Already rewarded this week (idempotent re-run).
			continue
		}

		if _, err := s.userRepo.CreateInboxReward(ctx, entry.UserID, repository.RewardWeeklyRank,
			weekStart.Format("2006-01-02"), strconv.Itoa(entry.Rank), coins); err != nil {
			slog.Error("weekly reset: CreateInboxReward failed", "userID", entry.UserID, "error", err)
		}
		if err := s.notifSvc.SendToUser(ctx, entry.UserID,
			"جایزه جدول هفته",
			fmt.Sprintf("نفر %s شدی و %s سکه گرفتی! از صندوق جایزه‌ها بردارش.", faNum(entry.Rank), faNum(coins)),
		); err != nil {
			slog.Warn("weekly reset: notification failed", "userID", entry.UserID, "error", err)
		}
		slog.Info("weekly reset: rewarded", "userID", entry.UserID, "rank", entry.Rank, "coins", coins)
	}

	if err := s.rdb.Del(ctx, weeklyRatingKey, weeklyWinsKey, weeklyGamesKey, legacyWeeklyKey).Err(); err != nil {
		slog.Error("weekly reset: Del Redis keys failed", "error", err)
	}
	slog.Info("leaderboard: weekly reset complete")
}
