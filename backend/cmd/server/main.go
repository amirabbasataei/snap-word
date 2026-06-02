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

	authSvc := service.NewAuthService(userRepo, cfg)
	gameSvc := service.NewGameService(matchRepo, statsRepo, streakSvc)
	powerupSvc := service.NewPowerupService(powerupRepo)
	_ = service.NewMonetizationService(userRepo) // available for handlers; no routes in Phase 16

	hub := ws.NewHub(ws.RoomDeps{
		MatchRepo:      matchRepo,
		PowerupSvc:     powerupSvc,
		StreakSvc:      streakSvc,
		LeaderboardSvc: leaderboardSvc,
	})

	matchSvc := service.NewMatchmakingService(rdb, hub)

	challengeRepo := repository.NewChallengeRepository(db)
	friendSvc := service.NewFriendService(friendRepo, userRepo, notifSvc)
	challengeSvc := service.NewChallengeService(challengeRepo, friendRepo, userRepo, hub, notifSvc)

	authHandler := handler.NewAuthHandler(authSvc)
	gameHandler := handler.NewGameHandler(gameSvc)
	powerupHandler := handler.NewPowerupHandler(powerupSvc)
	matchHandler := handler.NewMatchHandler(matchSvc)
	wsHandler := handler.NewWSHandler(hub, authSvc)
	leaderboardHandler := handler.NewLeaderboardHandler(leaderboardSvc)
	friendHandler := handler.NewFriendHandler(friendSvc)
	challengeHandler := handler.NewChallengeHandler(challengeSvc)
	notificationHandler := handler.NewNotificationHandler(notifRepo)

	// Start background scheduler
	sched := scheduler.New(leaderboardSvc, statsRepo, notifSvc, challengeSvc, rdb)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go sched.Start(ctx)

	api := router.Group("/api/v1")

	// Auth routes (public)
	auth := api.Group("/auth")
	auth.POST("/register", authHandler.Register)
	auth.POST("/login", authHandler.Login)
	auth.POST("/refresh", authHandler.Refresh)

	// Protected routes
	protected := api.Group("/", middleware.RequireAuth(authSvc))
	protected.POST("/game/solo", gameHandler.CreateSolo)
	protected.GET("/game/:id", gameHandler.GetGame)
	protected.GET("/profile/stats", gameHandler.GetStats)
	protected.GET("/powerup/inventory", powerupHandler.GetInventory)
	protected.POST("/powerup/use", powerupHandler.Use)
	protected.GET("/ws/game/:roomID", wsHandler.ServeWS)
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
