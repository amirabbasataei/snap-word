# AGENTS.md — WordChain

> **Read CLAUDE.md and PLAN.md at the start of every session** — and **REDESIGN_PLAN.md** while Phase 17 is in progress.  
> Phases 1–16 are complete. Phase 17 (زنجیر visual redesign) is in progress: Stages 1–5 done and verified on-device, Stage 6 code complete (needs a live multiplayer check), Stage 7 partial. Phases 18–21 are planned in PLAN.md. Never skip a phase scope.

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
│   │   │   ├── services/                dictionary, ws, sync, etc.
│   │   │   ├── theme/                   ZColors tokens, typography, spacing, elevation, motion, ThemeCubit
│   │   │   ├── utils/persian_digits.dart
│   │   │   └── widgets/                 shared LetterTile, SolidCard, AccentButton, ZBottomNav, …
│   │   └── features/
│   │       ├── auth/   game/   home/   lobby/
│   │       ├── daily/  leaderboard/  friends/  profile/
│   └── assets/words/fa.txt, assets/fonts/ (Vazirmatn)
├── figma/             legacy PNG design references (superseded by the canvas)
└── REDESIGN_PLAN.md   Phase 17 plan, tokens, decisions, stage notes
```

## Developer commands

```bash
# Backend (run from backend/)
go run ./cmd/server                          # start (reads backend/.env)
go test ./internal/...                       # all tests
go test ./internal/engine/...                # engine only
docker-compose up                            # full stack (app + postgres + redis)

# Flutter (run from client/)
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

`fa.txt` (Persian dictionary) must stay **byte-identical** between:
- `backend/internal/engine/data/fa.txt`
- `client/assets/words/fa.txt`

`fa.txt` is ~17.4k cleaned words (no ة, no diacritics) and is final — don't restore the old larger list. It is the only word data; the English frequency list and the rarity bonus were removed.

**Persian is multi-byte in Go**: never use `w[0]`, `w[len(w)-1]` or `len(w)` on words — use `engine.LastLetter`, `firstLetter`, `utf8.RuneCountInString`. AI trap letters are ژ ظ ث ذ ض (`config.AITrapLetters`, mirrored in Flutter's `aiTrapLetters`).

## Drift (Flutter local DB)

- `.g.dart` files are **gitignored**. After any schema change, run `dart run build_runner build` from `client/`.
- `LocalUsedWords` is the authoritative duplicate-check source. Always query it before the dictionary hash-set.
- When a match ends: update `local_matches.word_chain` (JSON) + delete `local_used_words` rows **in a single Drift transaction**.
- `SyncService.sync()` is idempotent; no-op for guests; fire-and-forget after game end (don't block UI).

## Game constants

Never hardcode magic numbers. Read from:
- Go: `internal/config/config.go` (`TurnTimerClassicSec`, `ContinueWindowSec`, etc.)
- Flutter: `lib/features/game/data/game_constants.dart` (`GameConstants`, incl. `soloLives`, `longWordBonusMinLength`, `multiplayerRoundsTotal`)

## Game rule changes (Phase 17)

- **Lives**: 2 lives (`GameConstants.soloLives`) for **solo Classic and Daily only**. Not vs-AI, Time Attack, or multiplayer (server-authoritative; no lives in the WS protocol).
- **Long-word bonus**: ≥7 letters doubles the turn score — Flutter scorer only; Go scorer unchanged.
- **No tutorial**: removed by product decision. Don't rebuild it.
- Wager/turn-length picker, best-of-5 rounds, levels/badges, typing indicator are **UI placeholders with no backend** — never fake them client-side.

## Guest mode

- Solo and vs-AI games run **entirely on-device** (no server calls).
- Guests get 5 free Hint uses per session (tracked in `GameBloc` state, not DB).
- Tapping "Find Match", "Leaderboard", "Friends", or "Daily Challenge" as guest → redirect to `/login?return=<destination>`.

## Auth

- Phone number + 4-digit OTP only (`POST /auth/send-otp`, `POST /auth/verify-otp`); email/password was removed. First verify = signup.
- Screens: `z_login_screen.dart` (`/login`), `z_otp_verify_screen.dart` (`/login/otp`). Dev bypass OTP: `1111` (no Kavenegar account yet).
- Referral codes: optional code at signup (+100 coins) or `POST /referral/redeem` once post-login (+50). Shared `ReferralBottomSheet`. Own code: `GET /referral/me`, shared from ZProfile `_InviteCard` via `ShareService.shareInvite`. Inviter gets +50 coins per invite as an unclaimed `referral_rewards` message (`GET /inbox`, `POST /inbox/:id/claim`; ZHome bell badge → `/inbox`).

## Power-up limits (multiplayer)

Server enforces one-use-per-type-per-match. Server rejects second use regardless of client state.

## Migrations (backend)

SQL files embedded via `io/fs` (`migrations/embed.go`). Auto-run at server startup. Numbered `NNN_name.up.sql` / `.down.sql`. Current: `001_init`, `002_friend_challenge_room`, `003_phone_auth_referral`, `004_ai_system_user` (the AI opponent is the fixed user `config.SystemAIUserID`, excluded from stats/leaderboard).

## Error handling

- **Go**: `fmt.Errorf("...: %w", err)`. Sentinels in service layer (`ErrInvalidWord`, `ErrNotYourTurn`). Handlers map to HTTP via `respondError`.
- **Flutter**: typed exceptions (`AuthException`, `NetworkException`, `ValidationException`). Cubits/Blocs catch and emit error states. Never let exceptions bubble to widgets.

## UI (Phase 17 visual system)

- Design source: the زنجیر Claude Design canvas (project `4a90de7c-3340-476f-922d-213a9dcd6307`). Fetch with `DesignSync` `get_file` (`path: "<Screen>.dc.html"`); WebFetch returns 403. `figma/` PNGs are legacy. Follow the designs; don't invent layouts.
- **Never hardcode colors in screens** — use `context.z.<token>` (`ZColors`). Light and dark mode are the same widgets with different token values. `AppColors` no longer exists; `test/core/theme/token_coverage_test.dart` enforces this.
- `ZOverScreen` is the single game-over/continue screen for solo, vs-AI and multiplayer.
- Vazirmatn font, Persian digits (`persian_digits.dart`), Jalali dates (`shamsi_date`), RTL-native (`EdgeInsetsDirectional`, `start`/`end`).
- Zero-blur elevation: solid offset edges only.
- Real data only — never fabricate stats the API doesn't provide.
- Verify UI changes on a device/simulator, not just with `flutter analyze`.
