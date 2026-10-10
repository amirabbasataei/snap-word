package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"

	"wordchain/backend/internal/adminui"
	"wordchain/backend/internal/config"
	"wordchain/backend/internal/handler"
	"wordchain/backend/internal/middleware"
	"wordchain/backend/internal/repository"
	"wordchain/backend/internal/scheduler"
	"wordchain/backend/internal/service"
	"wordchain/backend/internal/ws"
	dbmigrations "wordchain/backend/migrations"
)

func main() {
	cfg := config.Load()
	setupLogger(cfg.Env, cfg.LogLevel)

	slog.Info("starting wordchain backend", "env", cfg.Env, "port", cfg.Port)

	db, err := connectDB(cfg.DatabaseURL)
	if err != nil {
		slog.Error("database connection failed", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := runMigrations(db); err != nil {
		slog.Error("migrations failed", "error", err)
		os.Exit(1)
	}

	rdb, err := connectRedis(cfg.RedisURL)
	if err != nil {
		slog.Error("redis connection failed", "error", err)
		os.Exit(1)
	}
	defer rdb.Close()

	if cfg.Env == "prod" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())

	router.GET("/health", healthHandler(db, rdb))

	// Dependency wiring
	userRepo := repository.NewUserRepository(db)
	matchRepo := repository.NewMatchRepository(db)
	statsRepo := repository.NewStatsRepository(db)
	powerupRepo := repository.NewPowerupRepository(db)
	friendRepo := repository.NewFriendshipRepository(db)
	lbRepo := repository.NewLeaderboardRepository(db)
	notifRepo := repository.NewNotificationRepository(db)

	notifSvc := service.NewNotificationService(cfg, notifRepo)
	streakSvc := service.NewStreakService(statsRepo, userRepo, notifSvc)
	leaderboardSvc := service.NewLeaderboardService(rdb, userRepo, friendRepo, lbRepo, notifSvc)

	kavenegarClient := service.NewKavenegarClient(cfg)
	authSvc := service.NewAuthService(userRepo, kavenegarClient, rdb, cfg)
	gameSvc := service.NewGameService(matchRepo, statsRepo, streakSvc, repository.NewDailyRepository(db))
	powerupSvc := service.NewPowerupService(powerupRepo, userRepo)
	monetizationSvc := service.NewMonetizationService(userRepo)
	catalogSvc := service.NewCatalogService(repository.NewCatalogRepository(db))
	perksSvc := service.NewPerksService(userRepo, catalogSvc)

	hub := ws.NewHub(ws.RoomDeps{
		MatchRepo:      matchRepo,
		PowerupSvc:     powerupDeductor{powerupSvc},
		StreakSvc:      streakSvc,
		LeaderboardSvc: leaderboardSvc,
		XPSvc:          gameSvc,
		Coins:          userRepo,
		Perks:          userRepo,
		Taunts:         catalogSvc,
	})

	matchSvc := service.NewMatchmakingService(rdb, hub, userRepo)

	challengeRepo := repository.NewChallengeRepository(db)
	dailyRepo := repository.NewDailyRepository(db)
	friendSvc := service.NewFriendService(friendRepo, userRepo, notifSvc)
	challengeSvc := service.NewChallengeService(challengeRepo, friendRepo, userRepo, hub, notifSvc)
	dailySvc, err := service.NewDailyService(dailyRepo, statsRepo, userRepo, notifSvc, cfg)
	if err != nil {
		slog.Error("daily service init failed", "error", err)
		os.Exit(1)
	}

	authHandler := handler.NewAuthHandler(authSvc, cfg)
	gameHandler := handler.NewGameHandler(gameSvc)
	powerupHandler := handler.NewPowerupHandler(powerupSvc)
	monetizationHandler := handler.NewMonetizationHandler(monetizationSvc)
	perksHandler := handler.NewPerksHandler(perksSvc)
	adminRepo := repository.NewAdminRepository(db)
	adminAuthSvc := service.NewAdminAuthService(adminRepo, rdb, cfg)
	auditSvc := service.NewAuditService(adminRepo)
	catalogHandler := handler.NewCatalogHandler(catalogSvc, auditSvc)
	adminAuthHandler := handler.NewAdminAuthHandler(adminAuthSvc, auditSvc, cfg.AdminAPIKey)
	dashboardHandler := handler.NewAdminDashboardHandler(service.NewAdminDashboardService(adminRepo, hub, rdb, notifSvc))
	adminUsersHandler := handler.NewAdminUsersHandler(service.NewAdminUserService(adminRepo, userRepo, authSvc, auditSvc))
	adminContentSvc, err := service.NewAdminContentService(adminRepo, dailyRepo, leaderboardSvc, userRepo, rdb, auditSvc, cfg)
	if err != nil {
		slog.Error("admin content service init failed", "error", err)
		os.Exit(1)
	}
	adminContentHandler := handler.NewAdminContentHandler(adminContentSvc)
	matchHandler := handler.NewMatchHandler(matchSvc)
	wsHandler := handler.NewWSHandler(hub, authSvc)
	leaderboardHandler := handler.NewLeaderboardHandler(leaderboardSvc)
	friendHandler := handler.NewFriendHandler(friendSvc)
	challengeHandler := handler.NewChallengeHandler(challengeSvc)
	notificationHandler := handler.NewNotificationHandler(notifRepo)
	dailyHandler := handler.NewDailyHandler(dailySvc)

	// Start background scheduler
	sched := scheduler.New(leaderboardSvc, statsRepo, notifSvc, challengeSvc, dailySvc, rdb)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go sched.Start(ctx)

	api := router.Group("/api/v1")

	// Auth routes (public)
	auth := api.Group("/auth")
	auth.POST("/send-otp", authHandler.SendOTP)
	auth.POST("/verify-otp", authHandler.VerifyOTP)
	auth.POST("/refresh", authHandler.Refresh)

	// Not behind RequireAuth: a WebSocket handshake cannot carry an
	// Authorization header, so ServeWS authenticates itself via the
	// `?token=` query param instead (see ws.go). Mounting it under
	// `protected` previously made every real WS connection fail — the
	// header-only middleware rejected the handshake before ServeWS's own
	// query-param check ever ran.
	api.GET("/ws/game/:roomID", wsHandler.ServeWS)

	// Premium perk catalogues: public reads (the avatar image is loaded by a
	// plain image request), operator-only writes.
	api.GET("/perks/catalog", catalogHandler.Get)
	api.GET("/avatars/:id/image", catalogHandler.AvatarImage)

	// Admin API (Phase 23). Login is public but 404s until an admin exists or
	// a key is set; everything else needs a panel session or X-Admin-Key.
	adminAPI := api.Group("/admin", middleware.RequireAdminIP(cfg.AdminIPAllowlist))
	adminAPI.POST("/auth/login", middleware.RequireCSRFHeader(), adminAuthHandler.Login)
	admin := adminAPI.Group("", middleware.RequireAdmin(cfg.AdminAPIKey, adminAuthSvc))
	admin.POST("/auth/logout", adminAuthHandler.Logout)
	admin.GET("/auth/me", adminAuthHandler.Me)
	admin.GET("/dashboard/summary", dashboardHandler.Summary)
	admin.GET("/dashboard/timeseries", dashboardHandler.Timeseries)
	admin.GET("/users", adminUsersHandler.List)
	admin.GET("/users/:id", adminUsersHandler.Get)
	admin.GET("/taunts", adminContentHandler.Taunts)
	admin.GET("/avatars", adminContentHandler.Avatars)
	admin.GET("/avatars/:id/usage", adminContentHandler.AvatarUsage)
	admin.GET("/daily", adminContentHandler.DailyList)
	admin.GET("/daily/:date", adminContentHandler.DailyDetail)
	admin.GET("/leaderboards/weekly", adminContentHandler.WeeklyBoard)
	admin.GET("/leaderboards/alltime", adminContentHandler.AllTimeBoard)
	admin.GET("/leaderboards/rewards", adminContentHandler.WeeklyRewards)
	operator := admin.Group("", middleware.RequireRole(service.AdminRoleOperator))
	operator.PATCH("/daily/:date", adminContentHandler.SetStartLetter)
	operator.POST("/taunts/reorder", catalogHandler.ReorderTaunts)
	operator.POST("/users/:id/coins", adminUsersHandler.Coins)
	operator.POST("/users/:id/premium", adminUsersHandler.Premium)
	operator.PATCH("/users/:id/username", adminUsersHandler.Rename)
	operator.POST("/users/:id/avatar/clear", adminUsersHandler.ClearAvatar)
	operator.POST("/users/:id/ban", adminUsersHandler.Ban)
	operator.POST("/users/:id/unban", adminUsersHandler.Unban)
	operator.PUT("/taunts/:id", catalogHandler.PutTaunt)
	operator.DELETE("/taunts/:id", catalogHandler.DeleteTaunt)
	operator.PUT("/avatars/:id", catalogHandler.PutAvatar)
	operator.DELETE("/avatars/:id", catalogHandler.DeleteAvatar)

	// Admin panel SPA (embedded build of admin/), served at /admin.
	adminUI := handler.NewAdminUIHandler(adminui.FS(), func(c *gin.Context) bool {
		return middleware.AdminEnabled(c.Request.Context(), cfg.AdminAPIKey, adminAuthSvc)
	})
	handler.AdminUIRoutes(router, adminUI, cfg.AdminIPAllowlist)

	// Protected routes
	protected := api.Group("/", middleware.RequireAuth(authSvc))
	protected.POST("/referral/redeem", authHandler.RedeemReferral)
	protected.GET("/referral/me", authHandler.GetMyReferral)
	protected.GET("/rewards", authHandler.GetRewards)
	protected.POST("/rewards/:id/claim", authHandler.ClaimReward)
	protected.POST("/game/solo", gameHandler.CreateSolo)
	protected.GET("/game/:id", gameHandler.GetGame)
	protected.GET("/profile/stats", gameHandler.GetStats)
	protected.PATCH("/profile/username", authHandler.UpdateUsername)
	protected.GET("/profile/perks", perksHandler.Get)
	protected.PATCH("/profile/avatar", perksHandler.SetAvatar)
	protected.GET("/powerup/inventory", powerupHandler.GetInventory)
	protected.POST("/powerup/use", powerupHandler.Use)
	protected.POST("/rewarded-ad/claim", monetizationHandler.RewardedAd)
	protected.POST("/match/queue", matchHandler.JoinQueue)
	protected.DELETE("/match/queue", matchHandler.CancelQueue)
	protected.GET("/leaderboard", leaderboardHandler.Get)

	// Friends
	protected.POST("/friends/request", friendHandler.SendRequest)
	protected.GET("/friends", friendHandler.ListFriends)
	protected.GET("/friends/requests", friendHandler.ListRequests)
	protected.POST("/friends/respond", friendHandler.RespondToRequest)
	protected.DELETE("/friends/:friendId", friendHandler.RemoveFriend)

	// Friend challenges
	protected.POST("/challenges", challengeHandler.Create)
	protected.POST("/challenges/:id/respond", challengeHandler.Respond)
	protected.GET("/challenges/pending", challengeHandler.GetPending)
	protected.GET("/challenges/joinable", challengeHandler.GetJoinable)
	protected.GET("/challenges/:id", challengeHandler.Get)

	// Daily challenge
	protected.GET("/daily", dailyHandler.GetDaily)
	protected.POST("/daily/retry", dailyHandler.Retry)
	protected.GET("/daily/leaderboard", dailyHandler.GetLeaderboard)

	// Push notification token management
	protected.POST("/notifications/token", notificationHandler.RegisterToken)
	protected.DELETE("/notifications/token", notificationHandler.DeregisterToken)

	addr := fmt.Sprintf(":%s", cfg.Port)
	slog.Info("server listening", "addr", addr)
	if err := router.Run(addr); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func healthHandler(db *sql.DB, rdb *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if err := db.PingContext(ctx); err != nil {
			slog.Warn("health: db ping failed", "error", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "db_unavailable"})
			return
		}
		if err := rdb.Ping(ctx).Err(); err != nil {
			slog.Warn("health: redis ping failed", "error", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "redis_unavailable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	}
}

func setupLogger(env, level string) {
	var l slog.Level
	switch level {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	opts := &slog.HandlerOptions{Level: l}
	var handler slog.Handler
	if env == "prod" {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	} else {
		handler = slog.NewTextHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(handler))
}

func connectDB(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("db ping: %w", err)
	}
	slog.Info("database connected")
	return db, nil
}

func runMigrations(db *sql.DB) error {
	src, err := iofs.New(dbmigrations.FS, ".")
	if err != nil {
		return fmt.Errorf("iofs.New: %w", err)
	}
	driver, err := postgres.WithInstance(db, &postgres.Config{})
	if err != nil {
		return fmt.Errorf("migrate driver: %w", err)
	}
	m, err := migrate.NewWithInstance("iofs", src, "postgres", driver)
	if err != nil {
		return fmt.Errorf("migrate.NewWithInstance: %w", err)
	}
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("migrate up: %w", err)
	}
	slog.Info("migrations applied")
	return nil
}

func connectRedis(rawURL string) (*redis.Client, error) {
	opts, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, fmt.Errorf("redis.ParseURL: %w", err)
	}
	rdb := redis.NewClient(opts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	slog.Info("redis connected")
	return rdb, nil
}

// powerupDeductor adapts service.PowerupService to ws.PowerupDeductor (the ws
// package cannot import service without a cycle).
type powerupDeductor struct{ svc *service.PowerupService }

func (d powerupDeductor) UseItem(ctx context.Context, userID, powerupType string) (ws.PowerupReceipt, error) {
	use, err := d.svc.UseItem(ctx, userID, powerupType)
	if err != nil {
		return ws.PowerupReceipt{}, err
	}
	return ws.PowerupReceipt{Remaining: use.Remaining, Coins: use.Coins}, nil
}
