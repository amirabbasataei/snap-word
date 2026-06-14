# AGENTS.md — WordChain

> **Read CLAUDE.md and PLAN.md at the start of every session.**  
> This project was built phase-by-phase (1–16, all complete). Never skip a phase scope.

## Monorepo layout

```
wordchain/
├── backend/          Go module: wordchain/backend
│   ├── cmd/server/main.go       entrypoint
│   ├── internal/
│   │   ├── config/              env + game tuning consts
│   │   ├── handler/             Gin handlers (HTTP)
│   │   ├── service/             business logic
│   │   ├── repository/          Postgres/Redis
│   │   ├── ws/                  WebSocket hub/room/client
│   │   ├── engine/              dictionary, validator, scorer
│   │   ├── middleware/          JWT auth
│   │   └── scheduler/           background jobs
│   ├── migrations/              io/fs-embedded .sql files
│   └── docker-compose.yml       postgres:16 + redis:7 + app
├── client/           Flutter app
│   ├── lib/
│   │   ├── core/
│   │   │   ├── di/injection.dart        get_it registration
│   │   │   ├── network/                 dio_client, api_endpoints
│   │   │   ├── router/                  go_router
│   │   │   ├── database/                Drift (SQLite) + DAOs
│   │   │   └── services/                dictionary, ws, sync, etc.
│   │   └── features/
│   │       ├── auth/   game/   home/   lobby/
│   │       ├── daily/  leaderboard/  friends/  profile/
│   └── assets/words/enable.txt
└── figma/             UI design references
```

## Developer commands

```bash
# Backend (run from backend/)
cd backend
go run ./cmd/server                          # start (reads backend/.env)
go test ./internal/...                       # all tests
go test ./internal/engine/...                # engine only
docker-compose up                            # full stack (app + postgres + redis)

# Flutter (run from client/)
cd client
flutter run                                  # start app
dart run build_runner build                  # regenerate Drift .g.dart files
flutter analyze                              # lint + static analysis
flutter test                                 # widget/bloc tests
```

## Environment

- Backend env file: `backend/.env` (not root). See `.env.example` for all vars.
- Docker Compose forwards ports 8080, 5432, 6379 locally.

## Architecture rules (non-obvious, enforced)

- **Go**: handler → service → repository (strict 3-layer). No domain layer.
- **Flutter**: feature-based folders (`cubit/` or `bloc/`, `data/`, `view/`). No forced layering.
- **DI**: `get_it` only. Never `Provider` or `InheritedWidget`.
- **Navigation**: `go_router` only. Never `Navigator.push`.
- **Logging**: Go uses `slog` only (no `fmt.Println`). Flutter uses the `logger` package.

## Dictionary (dual)

`enable.txt` must stay **byte-identical** between:
- `backend/internal/engine/data/enable.txt`
- `client/assets/words/enable.txt`

`word_freq_ranks.txt` is backend-only. Rarity bonus is server-side only.

## Drift (Flutter local DB)

- `.g.dart` files are **gitignored**. After any schema change, run `dart run build_runner build` from `client/`.
- `LocalUsedWords` is the authoritative duplicate-check source. Always query it before the dictionary hash-set.
- When a match ends: update `local_matches.word_chain` (JSON) + delete `local_used_words` rows **in a single Drift transaction**.
- `SyncService.sync()` is idempotent; no-op for guests; fire-and-forget after game end (don't block UI).

## Game constants

Never hardcode magic numbers. Read from:
- Go: `internal/config/config.go` (`TurnTimerClassicSec`, `ContinueWindowSec`, etc.)
- Flutter: `lib/features/game/data/game_constants.dart`

## Guest mode

- Solo and vs-AI games run **entirely on-device** (no server calls).
- Guests get 5 free Hint uses per session (tracked in `GameBloc` state, not DB).
- Tapping "Find Match", "Leaderboard", "Friends", or "Daily Challenge" as guest → redirect to `/login?return=<destination>`.

## Power-up limits (multiplayer)

Server enforces one-use-per-type-per-match. Server rejects second use regardless of client state.

## Migrations (backend)

SQL files embedded via `io/fs` (`migrations/embed.go`). Auto-run at server startup. Numbered `NNN_name.up.sql` / `.down.sql`.

## Error handling

- **Go**: `fmt.Errorf("...: %w", err)`. Sentinels in service layer (`ErrInvalidWord`, `ErrNotYourTurn`). Handlers map to HTTP via `respondError`.
- **Flutter**: typed exceptions (`AuthException`, `NetworkException`, `ValidationException`). Cubits/Blocs catch and emit error states. Never let exceptions bubble to widgets.

## UI

All Flutter screens reference designs in `figma/`. Follow the designs; don't invent layouts.
