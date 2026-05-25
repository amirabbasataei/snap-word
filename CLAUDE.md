# CLAUDE.md — WordChain Project

This file is read by Claude Code at the start of every session.
**Always read this file first. Never skip a phase. Never implement ahead of the current phase.**

---

## 📌 Project Summary

A production-ready word-chain mobile game (Shiritori-style).
- Player enters a word starting with the last letter of the previous word
- Words must be valid (dictionary-checked), no repetition allowed
- Supports solo, multiplayer (1v1 real-time), and AI opponent modes

---

## 🧱 Tech Stack

| Layer | Choice |
|---|---|
| Mobile | Flutter — feature-based, flutter_bloc/cubit, go_router, dio, get_it |
| Backend | Go — Gin, handler→service→repository (no domain layer) |
| Realtime | WebSocket (gorilla/websocket) |
| Database | PostgreSQL 16 |
| Cache | Redis 7 |
| Dictionary | In-memory Go map, ENABLE wordlist (~170k words) |
| Auth | JWT (access + refresh tokens) |

---

## 📁 Final Project Structure (target)

```
wordchain/
├── CLAUDE.md                  ← this file
├── backend/
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── config/
│   │   ├── handler/
│   │   ├── service/
│   │   ├── repository/
│   │   ├── ws/
│   │   ├── engine/
│   │   └── middleware/
│   ├── migrations/
│   ├── Dockerfile
│   └── docker-compose.yml
└── frontend/
    └── lib/
        ├── main.dart
        ├── core/
        │   ├── di/
        │   ├── network/
        │   ├── router/
        │   ├── services/
        │   └── theme/
        └── features/
            ├── auth/
            ├── home/
            ├── game/
            ├── lobby/
            ├── leaderboard/
            └── profile/
```

---

## 📐 Coding Rules (apply in every session)

- Backend: strictly 3 layers — `handler → service → repository`. No domain layer.
- Frontend: feature-based folders only. No forced layered architecture per feature.
- Each feature only has what it needs: `cubit/` or `bloc/`, `data/`, `view/`.
- Use `get_it` for all DI. Never use `Provider` or `InheritedWidget` for DI.
- Use `go_router` for all navigation. Never call `Navigator.push` directly.
- Use a single `dio` instance registered in `get_it`, with an auth interceptor.
- WebSocket logic lives in `core/services/websocket_service.dart` only.
- Dictionary validation: Go `map[string]struct{}`, loaded once at startup, never queried from DB.
- Add comments only where logic is non-obvious.
- Write clean, readable, production-quality code. Avoid over-engineering.

---

## 🗄️ Database Schema (reference — implemented in Phase 1)

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    coins INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mode VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL,
    winner_id UUID REFERENCES users(id),
    game_state JSONB,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE match_players (
    match_id UUID REFERENCES matches(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    score INTEGER DEFAULT 0,
    is_ai BOOLEAN DEFAULT false,
    joined_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (match_id, user_id)
);

CREATE TABLE player_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    total_matches INTEGER DEFAULT 0,
    wins INTEGER DEFAULT 0,
    longest_word TEXT,
    best_streak INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE powerup_inventory (
    user_id UUID REFERENCES users(id),
    powerup_type VARCHAR(20) NOT NULL,
    quantity INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, powerup_type)
);
```

---

## 🌐 WebSocket Event Protocol (reference)

```
Client → Server:
  { "type": "submit_word",  "word": "apple" }
  { "type": "use_powerup",  "powerup": "freeze" }
  { "type": "ping" }

Server → Client:
  { "type": "game_start",            "state": { ... } }
  { "type": "word_accepted",         "word": "apple", "score": 85, "next_letter": "e" }
  { "type": "word_rejected",         "reason": "not_in_dictionary" | "wrong_letter" | "already_used" }
  { "type": "turn_change",           "player_id": "..." }
  { "type": "timer_update",          "remaining_ms": 7400 }
  { "type": "powerup_used",          "powerup": "freeze", "by": "..." }
  { "type": "game_over",             "winner": "...", "scores": { ... } }
  { "type": "opponent_disconnected" }
  { "type": "pong" }
```

---

## 💰 Scoring Formula (reference)

```
base_score   = word.length × 10
speed_bonus  = max(0, (time_limit - response_time_sec) × 2)
streak_bonus = streak >= 3 ? base_score × 0.5 : 0
rarity_bonus = word_frequency_rank > 10000 ? 20 : 0
turn_score   = base_score + speed_bonus + streak_bonus + rarity_bonus
```

---

## 🗺️ Implementation Phases

> **How to use:**
> At the start of each session, tell Claude Code:
> *"Read CLAUDE.md and implement Phase N."*
> Mark the phase `[x]` in this file when it is complete before starting the next session.

---

### Phase 1 — Foundation & Database
**Status: [ ] Not started**

**Scope:**
- Create the monorepo folder structure (`backend/`, `frontend/`)
- Write the full textual architecture diagram covering all components and data flows
- Initialize the Go module (`go.mod`) with all required dependencies
- Write `internal/config/config.go` — load from environment variables (DB URL, Redis URL, JWT secret, port)
- Write `migrations/001_init.sql` — full schema from the reference above
- Write `docker-compose.yml` — services: app, postgres, redis
- Write backend `Dockerfile`
- Write `cmd/server/main.go` — wire config, DB connection, Redis connection, and start Gin router (empty routes for now)

**Done when:** `docker-compose up` starts all three services, Go server boots and responds to `GET /health`.

---

### Phase 2 — Backend: Dictionary & Game Engine
**Status: [ ] Not started**

**Scope:**
- `internal/engine/dictionary.go` — download or embed the ENABLE wordlist; load into `map[string]struct{}` at startup; expose `IsValid(word string) bool`
- `internal/engine/validator.go` — `ValidateMove(prevWord, newWord string, usedWords map[string]bool) error` covering: correct starting letter, valid dictionary word, not already used
- `internal/engine/scorer.go` — `CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int` using the formula above
- Unit tests for all three engine files

**Done when:** All engine unit tests pass. Dictionary loads without error. Validator correctly rejects bad moves.

---

### Phase 3 — Backend: Auth
**Status: [ ] Not started**

**Scope:**
- `internal/repository/user.go` — `CreateUser`, `GetUserByEmail`, `GetUserByID`
- `internal/service/auth.go` — `Register`, `Login`, `RefreshToken` (bcrypt password hashing, JWT generation)
- `internal/handler/auth.go` — `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`
- `internal/middleware/auth.go` — JWT validation middleware for protected routes

**Done when:** Register and login return valid JWTs. Protected route returns 401 without token.

---

### Phase 4 — Backend: Game REST API & Match Repository
**Status: [ ] Not started**

**Scope:**
- `internal/repository/match.go` — `CreateMatch`, `GetMatch`, `UpdateMatchStatus`, `SaveGameState`, `GetMatchPlayers`
- `internal/repository/stats.go` — `UpsertStats`, `GetStats`
- `internal/service/game.go` — `CreateSoloGame`, `GetGameState`, `EndGame`, `UpdateStats`
- `internal/handler/game.go` — REST endpoints:
  - `POST /api/v1/game/solo` — start a solo game
  - `GET  /api/v1/game/:id` — get match state
  - `GET  /api/v1/profile/stats` — get current user's stats
- `internal/handler/powerup.go` — `POST /api/v1/powerup/use` (validates inventory, deducts, applies)

**Done when:** Can create a solo game, retrieve its state, and use a power-up via REST.

---

### Phase 5 — Backend: WebSocket & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `internal/ws/client.go` — WebSocket client wrapper (read/write pumps, ping/pong)
- `internal/ws/room.go` — game room: holds 2 clients, manages turn state, dispatches typed events, handles reconnection (30s grace window)
- `internal/ws/hub.go` — central hub: manages all rooms, routes messages, cleans up finished rooms
- `internal/handler/ws.go` — `GET /api/v1/ws/game/:roomID` — upgrades connection, registers client with hub
- Integrate engine validator and scorer into room turn logic
- Handle: timeout (auto-loss), invalid word, win/loss, opponent disconnect

**Done when:** Two clients can connect to the same room, exchange valid words, and receive `game_over` when one fails.

---

### Phase 6 — Backend: Matchmaking & AI Opponent
**Status: [ ] Not started**

**Scope:**
- `internal/service/matchmaking.go` — Redis List queue per mode; background goroutine polls every 500ms; pairs two players → creates room → notifies via WS; falls back to AI after 30s wait
- `internal/handler/game.go` additions — `POST /api/v1/match/queue`, `DELETE /api/v1/match/queue`
- `internal/service/ai.go` — AI player struct with difficulty config:
  ```
  Easy:   3s delay,  25% mistake rate, min word length 3
  Medium: 1.5s delay, 10% mistake rate, min word length 4
  Hard:   0.6s delay,  2% mistake rate, min word length 6
  ```
  AI picks a valid word from the dictionary filtered by required starting letter, applies mistake probability, waits simulated delay, submits via the room's input channel

**Done when:** Matchmaking pairs two real clients. Solo vs AI works at all three difficulty levels.

---

### Phase 7 — Backend: Leaderboard
**Status: [ ] Not started**

**Scope:**
- `internal/service/leaderboard.go` — Redis Sorted Set (`leaderboard:global:weekly`): `AddScore`, `GetTopN(n int)`, `GetPlayerRank(userID string)`
- Call `AddScore` at game end in the room's win/loss handler
- `internal/handler/leaderboard.go` — `GET /api/v1/leaderboard?limit=100` returns top N with rank + score + username

**Done when:** Leaderboard endpoint returns correct ranked list after a few completed games.

---

### Phase 8 — Flutter: Core Setup
**Status: [ ] Not started**

**Scope:**
- Initialize Flutter project in `frontend/`
- Add dependencies to `pubspec.yaml`: `flutter_bloc`, `go_router`, `dio`, `get_it`, `equatable`, `web_socket_channel`, `shared_preferences`
- `core/di/injection.dart` — register all services and repositories with `get_it`
- `core/network/dio_client.dart` — single `Dio` instance, base URL from env/config, auth interceptor (attaches JWT, handles 401 → refresh token)
- `core/network/api_endpoints.dart` — all endpoint constants
- `core/router/app_router.dart` — all routes via `go_router`: `/login`, `/register`, `/home`, `/game/:id`, `/lobby`, `/leaderboard`, `/profile`
- `core/services/websocket_service.dart` — connect, disconnect, send, stream of incoming typed events
- `core/theme/app_theme.dart` — light/dark theme

**Done when:** App builds, navigates between placeholder screens, DI resolves without errors.

---

### Phase 9 — Flutter: Auth Feature
**Status: [ ] Not started**

**Scope:**
- `features/auth/data/auth_repository.dart` — `register`, `login`, `refreshToken`; persist JWT in `shared_preferences`
- `features/auth/cubit/auth_cubit.dart` + `auth_state.dart` — states: `AuthInitial`, `AuthLoading`, `AuthAuthenticated`, `AuthError`
- `features/auth/view/login_screen.dart` — email + password fields, login button, link to register
- `features/auth/view/register_screen.dart` — username + email + password, register button
- On successful auth, navigate to `/home`; on app start, check stored token and auto-navigate

**Done when:** User can register, log in, and be redirected to home. Stored token survives app restart.

---

### Phase 10 — Flutter: Game Feature (Solo)
**Status: [ ] Not started**

**Scope:**
- `features/game/data/game_repository.dart` — `startSoloGame`, `getGame`, `usePowerup`
- `features/game/bloc/game_bloc.dart` + events + states — states: `GameInitial`, `GameLoading`, `GameActive`, `GameOver`, `GameError`
- Events: `GameStarted`, `WordSubmitted`, `PowerupUsed`, `TimerTicked`, `GameEnded`
- `features/game/view/game_screen.dart` — show current word chain, required starting letter, score, timer bar
- `features/game/view/widgets/word_input.dart` — text field with submit button; disable during opponent turn
- `features/game/view/widgets/word_chain_list.dart` — scrollable list of played words with player labels
- `features/game/view/widgets/timer_bar.dart` — animated countdown bar
- Wire `GameBloc` to `WebSocketService` for real-time events

**Done when:** Solo game is fully playable end-to-end from the UI.

---

### Phase 11 — Flutter: Lobby & Multiplayer
**Status: [ ] Not started**

**Scope:**
- `features/lobby/data/` — `joinQueue`, `cancelQueue`
- `features/lobby/cubit/lobby_cubit.dart` — states: `LobbyIdle`, `LobbySearching`, `LobbyMatchFound`, `LobbyError`
- `features/lobby/view/lobby_screen.dart` — mode selector (Classic / Time Attack / Daily), difficulty selector (for AI), Find Match button, searching animation, cancel button
- On `LobbyMatchFound`, navigate to `/game/:id`
- Add `features/home/view/home_screen.dart` — buttons for Solo vs AI, Find Match, Daily Challenge, Leaderboard, Profile

**Done when:** Player can queue, be matched, and land in a live game room.

---

### Phase 12 — Flutter: Leaderboard & Profile
**Status: [ ] Not started**

**Scope:**
- `features/leaderboard/cubit/leaderboard_cubit.dart` — fetch top 100, find current user's rank
- `features/leaderboard/view/leaderboard_screen.dart` — ranked list with avatar placeholder, username, score; highlight current user's row
- `features/profile/cubit/profile_cubit.dart` — fetch stats (total matches, wins, best streak, longest word, coin balance)
- `features/profile/view/profile_screen.dart` — stats display, power-up inventory, coin balance

**Done when:** Leaderboard and profile screens display real data from the backend.

---

### Phase 13 — Monetization Hooks & Final Wiring
**Status: [ ] Not started**

**Scope:**
- `core/services/monetization_service.dart` — abstract class + mock implementation:
  - `showRewardedAd() → Future<bool>`
  - `getProducts() → Future<List<Product>>`
  - `purchase(productId) → Future<PurchaseResult>`
  - `spendCoins(amount)`, `awardCoins(amount)`
- Register `MockMonetizationService` in `get_it` (swap for real SDK later)
- Add "Watch Ad to Continue" button on game-over screen (calls `showRewardedAd`)
- Add "Buy Coins" placeholder in profile screen
- Backend `internal/service/monetization.go` — stub `AwardCoins`, `SpendCoins`, `ValidateReceipt`
- Final integration test: full flow from register → queue → match → game → game over → leaderboard

**Done when:** All screens are connected, no placeholder crashes, the full game loop runs end-to-end.

---

## 🔁 Session Workflow

Each time you start a new Claude Code session:

1. Point Claude Code at this file: *"Read CLAUDE.md"*
2. State the phase: *"Implement Phase N — [title]"*
3. After the phase is complete, update the status line from `[ ] Not started` to `[x] Complete` in this file
4. Commit the code before starting the next session

---

## ⚠️ Important Notes for Claude Code

- **Never implement anything outside the current phase's scope.** If you notice something missing from a previous phase, flag it but do not fix it silently.
- **Always check previous phases' output** before writing new code that depends on it (e.g., check actual repository method signatures before calling them in a service).
- **Keep the CLAUDE.md status table up to date** after completing each phase.
- The backend dictionary wordlist (ENABLE) can be embedded as a `.txt` file in `internal/engine/data/` or downloaded at container build time — choose whichever is simpler.
- For local development, backend port is `8080`, Postgres is `5432`, Redis is `6379`.
