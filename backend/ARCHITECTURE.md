# WordChain Backend Architecture

## Overview

The backend is a Go service using a strict three-layer architecture:
**Handler → Service → Repository**. No domain layer.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Flutter Client                          │
│              (REST over HTTPS + WebSocket over WSS)             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Gin HTTP Server                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      Middleware                          │   │
│  │     auth.go (JWT)  ·  rate_limit.go  ·  cors.go         │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│  ┌────────────────────────────▼────────────────────────────┐   │
│  │                       Handlers                           │   │
│  │  auth.go · game.go · powerup.go · match.go ·            │   │
│  │  leaderboard.go · daily.go · friends.go ·               │   │
│  │  challenge.go · notification.go · ws.go                  │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                 │
│  ┌────────────────────────────▼────────────────────────────┐   │
│  │                       Services                           │   │
│  │  auth.go · game.go · ai.go · matchmaking.go ·           │   │
│  │  leaderboard.go · streak.go · friends.go ·              │   │
│  │  challenge.go · notification.go · monetization.go        │   │
│  └──────────┬─────────────────────────────┬────────────────┘   │
│             │                             │                     │
│  ┌──────────▼──────────┐    ┌────────────▼──────────────┐     │
│  │    Repositories      │    │    WebSocket Hub           │     │
│  │  user.go · match.go  │    │  hub.go · room.go ·       │     │
│  │  stats.go · friend.go│    │  client.go                │     │
│  │  challenge.go        │    └───────────────────────────┘     │
│  └──────────┬──────────┘                                       │
│             │                                                   │
│  ┌──────────▼──────────────────────────────────────────────┐   │
│  │                       Engine                             │   │
│  │  dictionary.go · frequency.go · validator.go · scorer.go│   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────┐  ┌───────────────────────────────┐   │
│  │      Scheduler       │  │          Config               │   │
│  │  scheduler.go        │  │  config.go (env-driven)       │   │
│  └─────────────────────┘  └───────────────────────────────┘   │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
   ┌──────────────────┐  ┌─────────────────┐  ┌────────────────┐
   │   PostgreSQL 16   │  │    Redis 7      │  │  FCM HTTP v1   │
   │  (primary store)  │  │ (cache/pub-sub/ │  │  (push notifs) │
   │                   │  │  leaderboard/  │  │                │
   │                   │  │  rate-limit)   │  │                │
   └──────────────────┘  └─────────────────┘  └────────────────┘
```

## Layer Responsibilities

### Handler layer (`internal/handler/`)
- Parses and validates HTTP request inputs
- Calls exactly one service method per handler
- Translates service errors to HTTP status codes via `respondError`
- Never contains business logic

### Service layer (`internal/service/`)
- Contains all business logic
- Defines sentinel errors (e.g. `ErrInvalidWord`, `ErrNotYourTurn`)
- Orchestrates repository calls; wraps errors with `fmt.Errorf("...: %w", err)`
- Unaware of HTTP or WebSocket transport

### Repository layer (`internal/repository/`)
- All SQL queries live here — no raw queries in services or handlers
- Returns typed errors; never HTTP codes
- Uses `*sql.DB` / `pgxpool.Pool` passed via constructor

### Engine (`internal/engine/`)
- Pure functions; no DB or network I/O
- Dictionary, frequency, validator, scorer
- Used by service layer for multiplayer; Flutter has a parallel client-side implementation for solo/AI

### WebSocket (`internal/ws/`)
- `hub.go` — owns all active rooms, routes messages
- `room.go` — single match room; shared chain logic, turn management, timers
- `client.go` — read/write pumps, ping/pong keepalive

### Scheduler (`internal/scheduler/`)
- 1-minute ticker goroutine started at boot
- Handles: midnight daily challenge push, streak-at-risk checks (1 min), challenge expiry (5 min), Sunday weekly reset

## Data Flow: Solo Game Sync

```
Flutter (offline)              Backend
──────────────────             ────────────────
Play solo game
  → local_matches (Drift)
  → local_used_words
  → local_player_stats
App foreground / login
  → SyncService.sync()
    POST /api/v1/game/solo ──► game handler
                                → game service
                                  → match repo (INSERT)
                                  → stats repo (UPSERT)
                               ◄── 200 { match_id }
    GET /api/v1/profile/stats ► stats handler
                               ◄── merged stats
    GET /api/v1/powerup/inventory ► powerup handler
                                  ◄── inventory
```

## Data Flow: Multiplayer Match

```
Client A                  Server (Hub/Room)              Client B
────────                  ─────────────────              ────────
POST /match/queue ──────► matchmaking service
                           (Redis list queue)
                                                POST /match/queue ◄── 
                           pair found
                           create room + match row
GET /ws/game/:id ───────► hub.RegisterClient              
                                              GET /ws/game/:id ◄──
                           emit game_start ──────────────────────►
◄─────────── game_start
{ "type": "submit_word" } ► room.handleWord
                             engine.ValidateMove
                             engine.CalculateScore
                           emit word_accepted ──────────────────►
◄─────── word_accepted      emit turn_change ───────────────────►
◄──────────── turn_change
```

## Database Connectivity

- **Primary pool**: `pgxpool.Pool` — used by all repository methods
- **Migrations**: `golang-migrate/migrate` with `lib/pq` driver; SQL files embedded via `//go:embed`
- **Redis**: `go-redis/v9` client — leaderboard sorted sets, rate-limit counters, notification dedup keys, matchmaking queues

## Configuration

All tuning values come from `internal/config/config.go` loaded from environment variables.
**Never hardcode** game timers, coin amounts, or limits in handlers, services, or widgets.

## Local Dev Ports

| Service    | Port |
|------------|------|
| Backend    | 8080 |
| PostgreSQL | 5432 |
| Redis      | 6379 |
