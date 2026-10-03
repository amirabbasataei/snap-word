# PLAN.md — WordChain Implementation Phases

Architecture specs, coding rules, DB schema, API contracts, and game design live in **CLAUDE.md**.
At the start of each session: read **both** files, then implement the requested phase.

> Mark each phase `[x] Complete` in both the CLAUDE.md status table and the per-phase status line below when done.
> Commit before starting the next phase.

---

## Phase 1 — Flutter: Core Setup
**Status: [x] Complete**

> **Later change:** the English ENABLE wordlist (`enable.txt`) was replaced by the Persian `fa.txt` (see CLAUDE.md Dictionary appendix). `core/theme/` was rewritten into the Phase 17 token system.

> Solo and AI games run entirely on-device. The backend is not involved until Phase 4+.
> This phase also creates the monorepo root structure.

**Scope:**
- Create monorepo root: `wordchain/` with `backend/` (empty placeholder) and `client/` folders; add `.env.example` and `.gitignore`
- Initialize Flutter project in `client/`
- `pubspec.yaml` dependencies: `flutter_bloc`, `go_router`, `dio`, `get_it`, `equatable`, `web_socket_channel`, `shared_preferences`, `logger`, `firebase_messaging`, `share_plus`, `drift`, `drift_flutter`, `sqlite3_flutter_libs`, `connectivity_plus`; dev dependencies: `drift_dev`, `build_runner`
- `core/database/app_database.dart` — Drift `AppDatabase`; registers all four tables; schema version 1; opens via `driftDatabase(name: 'wordchain.db')`
- `core/database/daos/match_dao.dart` — `createMatch`, `updateMatch`, `getActiveMatch`, `getUnsyncedMatches`, `markSynced(id, remoteId)`
- `core/database/daos/used_word_dao.dart` — `insertWord(matchId, word)`, `isWordUsed(matchId, word) → Future<bool>`, `deleteWordsForMatch(matchId)`
- `core/database/daos/stats_dao.dart` — `getStats`, `upsertStats`, `mergeWithRemote(RemoteStats)` (takes MAX of each numeric field)
- `core/database/daos/powerup_cache_dao.dart` — `getAll`, `setQuantity`, `refreshFromRemote`
- `core/services/sync_service.dart` — `sync()`: (1) uploads unsynced `local_matches` to `POST /api/v1/game/solo`, (2) merges remote stats via `StatsDao`, (3) refreshes powerup cache via `PowerupCacheDao`; no-op if guest
- `core/di/injection.dart` — register all services and repositories, including `AppDatabase` and `SyncService` as lazy singletons
- `core/network/dio_client.dart` — single `Dio` instance, base URL from config, auth interceptor (attaches JWT, handles 401 → refresh)
- `core/network/api_endpoints.dart` — all endpoint constants
- `core/router/app_router.dart` — routes: `/login`, `/register`, `/home`, `/game/:id`, `/lobby`, `/daily`, `/leaderboard`, `/friends`, `/profile`
- `core/services/websocket_service.dart` — connect, disconnect, send, stream of typed incoming events
- `core/services/dictionary_service.dart` — load ENABLE into `HashSet<String>` before `runApp()`, expose `isValid(String word) bool` and `suggestWords(String startLetter) List<String>`
- `core/services/notification_service.dart` — request FCM permission after tutorial, register token via API, handle foreground messages as in-app banners, expose notification payload stream for deep-link routing
- `core/services/share_service.dart` — `shareDaily(DailyChallengeResult result)` using `share_plus`
- `core/theme/app_theme.dart` — light/dark theme
- Bundle `assets/words/enable.txt` in `pubspec.yaml`

**Design reference:** `figma/home-screen.png`, `figma/onboarding.png`

**Done when:** App builds, all routes navigate to placeholder screens, DI resolves, `isValid("apple")` returns true, `AppDatabase` opens without error, `isWordUsed` returns `false` on a fresh match, `SyncService.sync()` is a no-op for a guest.

---

## Phase 2 — Flutter: Game Feature (Solo + Tutorial)
**Status: [x] Complete**

> **Later changes (Phase 17):** solo Classic/Daily now use 2 lives instead of instant game-over; `game_screen.dart` now routes to `z_solo_screen.dart`/`z_play_screen.dart`/`z_over_screen.dart`. The tutorial was dropped by product decision: `tutorial_screen.dart`, the `/tutorial` route, and Profile → Help were deleted in `fa5811d`.

**Scope:**
- `features/game/data/game_repository.dart` — `startLocalGame(mode, opponentType) → Future<int>`: inserts a row into `local_matches` (status `active`) and returns its local id; `finishLocalGame(localMatchId, score, wordChain)`: updates status, score, chainLength, wordChain, endedAt and runs `deleteWordsForMatch` — all inside one Drift transaction; `usePowerup(type)` (authenticated only): calls `POST /api/v1/powerup/use` then updates `local_powerup_cache` on success
- `features/game/bloc/game_bloc.dart` — states: `GameInitial`, `GameLoading`, `GameActive`, `GameOver`, `GameError`; events: `GameStarted`, `WordSubmitted`, `PowerupUsed`, `TimerTicked`, `GameEnded`, `ContinueRequested`, `ContinueResolved`
  - On `GameStarted`: calls `game_repository.startLocalGame()`, stores `localMatchId` in bloc state
  - On `WordSubmitted`: first calls `UsedWordDao.isWordUsed(localMatchId, word)` for duplicate check, then `DictionaryService.isValid(word)` for dictionary check; on acceptance inserts via `UsedWordDao.insertWord()`
  - On `GameEnded`: calls `game_repository.finishLocalGame()` (Drift transaction: update match + delete used words), then `StatsDao.upsertStats()`, then `SyncService.sync()` as a fire-and-forget (do not await in bloc)
- `features/game/view/game_screen.dart` — word chain display, required starting letter, score, timer bar, power-up buttons, game-over overlay with continue prompt
- `features/game/view/widgets/word_input.dart` — text field + submit; disabled during opponent's turn
- `features/game/view/widgets/word_chain_list.dart` — scrollable list of played words
- `features/game/view/widgets/timer_bar.dart` — animated countdown bar
- `features/game/view/widgets/continue_prompt.dart` — shown on `GameOver` in Classic mode; "Watch Ad" and "Spend 25 Coins" buttons; 15-second countdown; one use per session tracked in `GameBloc` state
- Tutorial flow at `features/game/view/tutorial_screen.dart` (see CLAUDE.md Tutorial section for 4-step spec)
  - Sandboxed in-memory state, no record created
  - Shown on first launch via `shared_preferences: tutorial_completed`
  - Skippable and replayable from Profile → Help
- Guest Hint: 5 free per session, soft upsell prompt on last use

**Design reference:** `figma/solo-game.png`, `figma/game-over.png`

**Done when:** Solo game fully playable by a guest, including resuming an interrupted game after app restart. Used-word duplicate detection reads from `local_used_words`, not from memory. Stats persist in `local_player_stats` after app restart. Tutorial completes all four steps. Continue works once per Classic session. All end conditions trigger `GameOver`.

---

## Phase 3 — Flutter: Auth Feature
**Status: [x] Complete**

> **Superseded (Phase 17 Stage 4):** email/password auth was fully removed. Auth is now phone + OTP via `z_login_screen.dart` (`/login`) and `z_otp_verify_screen.dart` (`/login/otp`); `login_screen.dart`, `register_screen.dart`, and `/register` no longer exist. See CLAUDE.md § Guest Mode & Auth Strategy.

> Auth UI and cubit are fully implementable now. The actual API calls (`register`, `login`, `refreshToken`) will return network errors until Phase 4 brings the backend up — guest mode continues to work perfectly throughout.

**Scope:**
- `features/auth/data/auth_repository.dart` — `register`, `login`, `refreshToken`; persist JWT in `shared_preferences`
- `features/auth/cubit/auth_cubit.dart` — states: `AuthInitial`, `AuthLoading`, `AuthGuest`, `AuthAuthenticated`, `AuthError`; expose `isGuest` flag
- `features/auth/view/login_screen.dart` — email + password, login button, register link, "Continue as Guest" button
- `features/auth/view/register_screen.dart` — username + email + password, register button, "Continue as Guest" link
- App startup logic: valid JWT → `AuthAuthenticated` → `/home` then `SyncService.sync()`; no token / refresh failed → `AuthGuest` → `/home`
- On register or login success: call `SyncService.sync()` — all unsynced `local_matches` are uploaded and stats are merged automatically, regardless of which session the games were played in

**Design reference:** `figma/login-screen.png`

**Done when:** Guest reaches home and plays solo without login. Auth screens render correctly and handle network errors gracefully. Token persistence logic is wired (full login flow verified end-to-end after Phase 4). All unsynced matches and stats upload automatically on registration and login once the backend is running.

---

## Phase 4 — Foundation & Database
**Status: [x] Complete**

> `client/` and monorepo root already exist from Phase 1. This phase builds out the `backend/` scaffold and brings the server online so Phases 3 and 5+ can be tested end-to-end.

**Scope:**
- Write full architecture diagram (`backend/ARCHITECTURE.md`)
- Initialize Go module (`go.mod`) with all dependencies inside `backend/`
- `internal/config/config.go` — load from env vars (see CLAUDE.md Appendix)
- `migrations/001_init.up.sql` + `001_init.down.sql` — full schema from CLAUDE.md Database Schema section (all tables including `friendships`, `friend_challenges`, `device_tokens`, `weekly_leaderboard_rewards`)
- `docker-compose.yml` — services: app, postgres, redis
- Backend `Dockerfile`
- `cmd/server/main.go` — wire config, DB, Redis, Gin router, `GET /health`

**Done when:** `docker-compose up` starts all three services. Server responds to `GET /health` with 200 OK. Auth flow from Phase 3 works against the running server.

---

## Phase 5 — Backend: Dictionary & Game Engine
**Status: [x] Complete**

> The Go dictionary is used **only for multiplayer validation**. Solo and AI games validate entirely on the Flutter client.

**Scope:**
- `internal/engine/dictionary.go` — embed ENABLE wordlist (`data/enable.txt`), load into `map[string]struct{}` at startup, expose `IsValid(word string) bool`
- ~~`internal/engine/frequency.go`~~ (removed 2026-09-28 with the English frequency list) — embed `data/word_freq_ranks.txt`, load into `map[string]int` at startup, expose `Rank(word string) int` (returns `math.MaxInt` if missing)
- `internal/engine/validator.go` — `ValidateMove(prevWord, newWord string, usedWords map[string]bool) error` — covers all six Word Validation Rules from CLAUDE.md; returns typed sentinel errors
- `internal/engine/scorer.go` — `CalculateScore(word string, responseTimeSec float64, streak int, timeLimitSec float64) int` using the scoring formula from CLAUDE.md (includes rarity_bonus via `frequency.Rank`)
- Unit tests for all four engine files

**Done when:** All engine unit tests pass. Dictionary loads. Validator correctly rejects bad moves with typed errors.

---

## Phase 6 — Backend: Auth
**Status: [x] Complete**

> **Superseded (Phase 17 Stage 4):** `Register`/`Login`/bcrypt were replaced by `SendOTP`/`VerifyOTP` (`POST /auth/send-otp`, `POST /auth/verify-otp`), plus `POST /referral/redeem`. Migration `003_phone_auth_referral` drops `email`/`password_hash`. See CLAUDE.md § Guest Mode & Auth Strategy and § Referral Code System.

**Scope:**
- `internal/repository/user.go` — `CreateUser`, `GetUserByEmail`, `GetUserByID`
- `internal/service/auth.go` — `Register`, `Login`, `RefreshToken` (bcrypt, JWT generation)
- `internal/handler/auth.go` — `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/refresh`
- `internal/middleware/auth.go` — JWT validation middleware for protected routes
- Password policy: min 8 chars, ≥1 letter and ≥1 digit. Username: 3–32 chars, `[a-zA-Z0-9_]`.

**Done when:** Register and login return valid JWTs. Protected route returns 401 without token. Invalid passwords rejected with 400.

---

## Phase 7 — Backend: Game REST API & Match Repository
**Status: [x] Complete**

**Scope:**
- `internal/repository/match.go` — `CreateMatch`, `GetMatch`, `UpdateMatchStatus`, `SaveGameState`, `GetMatchPlayers`, `SetContinueUsed`
- `internal/repository/stats.go` — `UpsertStats`, `GetStats`
- `internal/service/game.go` — `CreateSoloGame`, `GetGameState`, `EndGame`, `UpdateStats`
- REST endpoints: `POST /api/v1/game/solo`, `GET /api/v1/game/:id`, `GET /api/v1/profile/stats`
- `internal/handler/powerup.go` — `GET /api/v1/powerup/inventory`; `POST /api/v1/powerup/use` (validates inventory, deducts, applies; rejects second use in multiplayer)
- `POST /api/v1/game/solo` accepts `{mode, score, word_chain: [...], started_at, ended_at}`; returns `409` if a match with the same `started_at` + `user_id` already exists (idempotent sync upload)

**Done when:** Solo game create/retrieve/end and power-up use work via REST.

---

## Phase 8 — Backend: WebSocket & Multiplayer
**Status: [x] Complete**

**Scope:**
- `internal/ws/client.go` — read/write pumps, ping/pong
- `internal/ws/room.go` — shared chain room: alternating turns on a single chain, `loss_event` dispatch, continue handling (15s window, one continue per player tracked via `match_players.continue_used`), Shield interaction, reconnection (30s grace)
- `internal/ws/hub.go` — manages all rooms, routes messages, cleans up finished rooms
- `internal/handler/ws.go` — `GET /api/v1/ws/game/:roomID` — upgrades connection, registers client with hub
- Integrate engine validator and scorer into room turn logic
- Handle client events: `submit_word`, `use_powerup`, `continue`
- Emit server events: `word_accepted`, `word_rejected`, `loss_event`, `continue_window`, `continue_decision`, `game_over`
- Reject `use_powerup` if player already used that power-up type in this match

**Done when:** Two clients share a single chain, alternate correctly, loss events trigger the continue window, one continue per player enforced, game_over fires.

---

## Phase 9 — Backend: Matchmaking & AI Opponent
**Status: [x] Complete**

**Scope:**
- `internal/service/matchmaking.go` — Redis List queue (`queue:classic`; Time Attack removed 2026-10-03); background goroutine polls every 500ms; pairs two players → creates room → notifies via WS; falls back to AI opponent after 30s wait
- `POST /api/v1/match/queue`, `DELETE /api/v1/match/queue`
- `internal/service/ai.go` — AI difficulty struct (see CLAUDE.md AI Opponent section):
  ```
  Easy:   3s delay, 25% mistake rate, min length 3, random word selection
  Medium: 1.5s delay, 10% mistake rate, min length 4, 30% trap-letter preference
  Hard:   0.6s delay, 2% mistake rate, min length 6, 70% trap-letter preference + longest valid trap word preferred
  ```
  Trap letters: Q, X, Z, J, V (later replaced by Persian ژ ظ ث ذ ض — see CLAUDE.md AI Opponent). AI selects a trap-ending word only when at least one exists; otherwise falls back to weighted random.

**Done when:** Matchmaking pairs two real clients. AI plays at all three difficulty levels with correct trap letter behaviour.

---

## Phase 10 — Backend: Leaderboard & Streak
**Status: [x] Complete**

**Scope:**
- `internal/service/leaderboard.go` — Redis Sorted Set `leaderboard:global:weekly`: `AddScore`, `GetTopN(n int)`, `GetPlayerRank(userID string)`
- `AddScore` called at end of **multiplayer and Daily Challenge games only** (not solo)
- `GET /api/v1/leaderboard?type=global&limit=100`
- `GET /api/v1/leaderboard?type=friends&limit=100` — fetches friend IDs, retrieves scores via `ZSCORE`
- `internal/service/streak.go` — `RecordGamePlayed(userID string, date time.Time)`: updates `daily_streak`, `last_played_date`, `longest_daily_streak`; awards milestone coins; calls `notification.SendToUser` for milestone events
- Call `RecordGamePlayed` at every game end (solo, multiplayer room close, daily challenge)
- `internal/scheduler/scheduler.go` — goroutine with 1-minute ticker:
  - Weekly reset: Sunday 00:00 UTC — query top 3, insert `weekly_leaderboard_rewards`, award coins, send push notifications, delete Redis key
  - Streak at-risk check: every minute, fire notifications where applicable

**Done when:** Leaderboard returns correct ranked list. Weekly reset awards coins and sends notifications. Streak increments and milestone coins are awarded.

---

## Phase 11 — Backend: Friends & Challenges
**Status: [x] Complete**

**Scope:**
- `internal/repository/friendship.go` — `SendRequest`, `RespondToRequest`, `ListFriends`, `ListPendingRequests`, `RemoveFriend`
- `internal/repository/challenge.go` — `CreateChallenge`, `RespondToChallenge`, `GetPendingChallenges`, `ExpireOldChallenges`
- `internal/service/friends.go` — no duplicate requests, no self-requests, validates friendship before challenge creation
- `internal/service/challenge.go` — `CreateChallenge` (creates private match room on accept, writes `match_id`), `RespondToChallenge` (accept → direct private room; decline → notify challenger), push notifications on all state changes
- Handlers for all Friends and Friend Challenge endpoints
- Scheduler job: run `ExpireOldChallenges` every 5 minutes; notify challenger on expiry

**Done when:** Full friend request and friend challenge flows work end-to-end. Expired challenges are cleaned up automatically.

---

## Phase 12 — Backend: Push Notifications
**Status: [x] Complete**

**Scope:**
- `internal/service/notification.go` — `SendToUser(userID, title, body string)`: looks up FCM token from `device_tokens`, calls FCM HTTP v1 API using `FCM_SERVICE_ACCOUNT_JSON` for auth
- `POST /api/v1/notifications/token`, `DELETE /api/v1/notifications/token`
- Wire `SendToUser` into all existing stub trigger points: friend request, challenge received/responded, match found, streak milestone, weekly leaderboard reward
- Scheduler jobs:
  - **Midnight UTC daily**: send Daily Challenge reminder to all users with tokens
  - **Every minute**: send streak-at-risk notification (deduplicate with Redis key `notif:streak_risk:{userID}:{date}`, TTL 24h)

**Done when:** All notification triggers fire in integration tests. Token registration and deregistration work. Duplicate at-risk notifications are prevented.

---

## Phase 13 — Flutter: Lobby & Multiplayer
**Status: [x] Complete**

**Scope:**
- `features/lobby/data/lobby_repository.dart` — `joinQueue`, `cancelQueue`
- `features/lobby/cubit/lobby_cubit.dart` — states: `LobbyIdle`, `LobbySearching`, `LobbyMatchFound`, `LobbyError`
- `features/lobby/view/lobby_screen.dart` — Classic is the only mode (no selector; Daily Challenge does not appear here), entry-fee info row, Find Match button, searching animation, cancel button, friends list with real challenge invites
- On `LobbyMatchFound`, navigate to `/game/:id`
- Multiplayer additions to `game_screen.dart`:
  - Shared chain display: words labeled by player
  - Turn indicator
  - Both players' power-up inventories displayed
  - Opponent continue-window overlay: "Opponent deciding… [15s countdown]"
- Wire `GameBloc` to `WebSocketService` for multiplayer; handle `loss_event`, `continue_window`, `continue_decision`, `game_over`
- `features/home/view/home_screen.dart` — Solo / vs AI, Find Match, Daily Challenge, Leaderboard, Friends, Profile; show daily streak count if authenticated
- Before calling `lobby_repository.joinQueue()`, trigger `SyncService.sync()`

**Design reference:** `figma/match-making.png`, `figma/multiplayer-game.png`

**Done when:** Player queues, is matched, plays a shared-chain multiplayer game, continue window works for both players, game_over navigates correctly, local stats are synced before joining the queue.

---

## Phase 14 — Flutter: Leaderboard, Friends & Profile
**Status: [x] Complete**

**Scope:**
- `features/leaderboard/cubit/leaderboard_cubit.dart` — fetch global top 100 and friends top 100; current user rank in each
- `features/leaderboard/view/leaderboard_screen.dart` — tab bar: Global | Friends; ranked list; highlight current user's row; weekly reward note for top 3
- `features/friends/data/friends_repository.dart` — all Friend and Friend Challenge API calls
- `features/friends/cubit/friends_cubit.dart`
- `features/friends/view/friends_screen.dart` — friend list, pending requests banner, username search, per-friend profile with Challenge button
- `features/friends/view/friend_challenge_sheet.dart` — Classic challenge confirmation, send challenge button
- `features/profile/cubit/profile_cubit.dart` — authenticated: fetch stats/coins/powerups from backend, update local cache; guest: read from `StatsDao`, show "Register to back up" banner
- `features/profile/view/profile_screen.dart` — stats, coin balance, powerup inventory (authenticated); guest banner; Help button (replays tutorial — removed in Phase 17)
- Handle notification deep links: friend request/challenge notification → `/friends`

**Design reference:** `figma/leaderboard.png`, `figma/friends-screen.png`, `figma/profile-screen.png`

**Done when:** All screens show real data. Friend request and challenge flows complete end-to-end.

---

## Phase 15 — Flutter: Daily Challenge & Sharing
**Status: [x] Complete**

**Scope:**
- `features/daily/data/daily_repository.dart` — `getDailyChallenge`, `submitAttempt`, `retryChallenge`
- `features/daily/cubit/daily_cubit.dart` — states: `DailyInitial`, `DailyLoading`, `DailyAvailable`, `DailyAttempted`, `DailyRetryAvailable`, `DailyError`
- `features/daily/view/daily_screen.dart`:
  - Not attempted: shows today's challenge details and Play button
  - Attempted: shows score, chain length, word chain, Share button, optional Retry (25 coins)
  - Retry attempted: shows retry score alongside original, Share button only
- After game completion: navigate to daily result screen, trigger share card display
- `share_service.dart` generates the text card (see CLAUDE.md Social Features → Daily Challenge share card) and calls `Share.share()`
- Handle notification deep link: daily push → `/daily`
- Wire daily streak display on Home and Profile

**Design reference:** `figma/daily-challenge.png`, `figma/daily-result.png`

**Done when:** Daily Challenge plays end-to-end. Share card generates correctly. Retry deducts 25 coins. Streak increments after any game completion. Deep link navigates to `/daily`.

---

## Phase 16 — Monetization Hooks & Final Wiring
**Status: [x] Complete**

**Scope:**
- `core/services/monetization_service.dart` — abstract class + mock implementation:
  - `showRewardedAd() → Future<bool>` — returns true if full ad watched
  - `showInterstitialAd()` — between sessions only, never mid-game
  - `getProducts() → Future<List<Product>>`
  - `purchase(productId) → Future<PurchaseResult>`
  - `spendCoins(int amount) → bool`
  - `awardCoins(int amount)`
- Register `MockMonetizationService` in `get_it`; swap for AdMob + RevenueCat in production
- Game-over screen: "Watch Ad to Continue" + "Spend 25 Coins" buttons; interstitial ad when returning to home (not when continuing)
- Profile screen: coin balance display, "Buy Coins" (mock: $0.99 / $2.99 / $9.99), "Remove Ads" one-time purchase, "Premium — $3.99/mo" subscription
- Backend `internal/service/monetization.go` — `AwardCoins`, `SpendCoins`, `ValidateReceipt` (stub)
- Run full integration test suite (see below)

**Done when:** All screens connected, no placeholder crashes, every earn/spend coin path updates balances correctly, full guest and registered game loops run end-to-end.

---

## Integration Tests (Phase 16)

Full end-to-end smoke flows:
- Guest → solo → game over → watch ad continue → game ends → score shown
- Guest → completes solo → registers → score transferred to new account
- Registered → Daily Challenge → completes → share card generated → retry costs 25 coins
- Registered → matchmaking queue → 1v1 match → shared chain play → continue prompt → game over → leaderboard updated
- Registered → sends friend request → friend accepts → friend challenge → private match
- Weekly scheduler job runs → top 3 rewarded → leaderboard resets

---

## Phase 17 — Visual Redesign (زنجیر)
**Status: [ ] In Progress — Stages 1–5 complete and on-device verified; Stage 6 code complete (multiplayer game-over/overlays on tokens, legacy `AppColors` removed) — needs a live multiplayer match to verify; Stage 7 partial (shared-widget goldens + token lint done, chain-renderer goldens remaining)**

Full plan, token values, spec-conflict decisions, and per-stage notes live in **REDESIGN_PLAN.md**. Summary:

- Ports the Claude Design canvas (`Zanjir.dc.html` and per-screen files, project `4a90de7c-3340-476f-922d-213a9dcd6307`, fetched via the `DesignSync` `get_file` method) into Flutter as a token-driven light+dark visual system, RTL-native, Vazirmatn typeface. Blocs/cubits/repositories/DI stay unchanged except where a stage fixed a real bug or adopted a mechanic.

| Stage | Scope | Status |
|---|---|---|
| 1 — Foundation | `core/theme/` token system (`ZColors`), Vazirmatn, `persian_digits.dart`, `ThemeCubit`, RTL audit, `ZBottomNav`, shared widgets in `core/widgets/` | [x] Complete |
| 2 — Core loop | ZHome, ZSolo (`z_solo_screen.dart`), ZPlay (`z_play_screen.dart`), ZOver (`z_over_screen.dart`) | [x] Complete, on-device verified |
| 3 — Daily Challenge | ZDailyBefore / ZDailyAfter (`daily_screen.dart`), Jalali date, lives extended to Daily | [x] Complete, on-device verified |
| 4 — Multiplayer + auth | ZLobby, ZVersus (`z_versus_screen.dart`); ZLogin / ZOtp (phone + OTP auth, email/password removed); referral system | [x] Complete, on-device verified 2026-09-17 (auth screens tap-through by AmirAbbas) |
| 5 — Secondary screens | ZBoard (`z_board_screen.dart`), ZProfile (`z_profile_screen.dart`, incl. حالت شب toggle), ZFriends (`z_friends_screen.dart`) | [x] Complete — verified on the Android emulator 2026-09-28, both themes |
| 6 — Undesigned screens | Multiplayer game-over + continue → `ZOverScreen`; opponent-deciding overlay, disconnect banner, friend challenge sheet on tokens; legacy `AppColors` + dead widgets removed. (Tutorial dropped — not rebuilt.) | [ ] Code complete 2026-09-28; needs a live multiplayer match (win, loss, continue, disconnect) to verify |
| 7 — Tests | Create goldens (none exist yet — `client/test` has no golden files) for the chain renderers, light+dark goldens for `core/widgets/`, lint against `Color(0x…)` in `features/` | [ ] Partial — shared-widget goldens, token-coverage test, ZOver widget tests done; chain-renderer goldens + other Z-screen widget tests remaining |

**Adopted / decided mechanic changes (see REDESIGN_PLAN.md §1 and stage notes for rationale):**
- **Lives** — `GameConstants.soloLives = 2` for **solo Classic and Daily** only. Not applied to vs-AI or multiplayer (server-authoritative; Go WS protocol has no lives concept — «۲ جان» omitted from ZVersus rather than faked).
- **Long-word bonus** — ≥7 letters doubles the turn score, **Flutter scorer only** (`GameBloc._calculateScore`). Go scorer unchanged; follow-up.
- **Wager + turn-length picker** (ZLobby) — **removed 2026-10-03.** Time Attack was removed from the whole app (Classic only, fixed 15s turn) and the wager became a real fixed **entry fee** (20 coins per human player, winner takes the 40-coin pot, free vs AI) — see REDESIGN_PLAN.md "Post-Stage-7 changes". A room-code invite was built and then removed the same day.
- **Best-of-5 rounds** (ZVersus) — fixed constant (`GameConstants.multiplayerRoundsTotal = 5`), rendered as a static «دست ۱ از ۵» placeholder; round tracking is follow-up backend work.
- **Levels & badges** (ZProfile) — rendered as designed, wired to placeholders; schema + backend is follow-up.
- **Referral codes** — **fully implemented**: migration `003_phone_auth_referral`, signup-time code on `POST /auth/verify-otp` (+100 coins) and `POST /referral/redeem` post-login (+50, one-time), shared `ReferralBottomSheet` client widget. ZLobby's room-code invite row was removed (2026-10-03).
- **Typing indicator** (ZVersus) — not built (needs a new WS event).
- **Real-data-only** — canvas stats with no API field (player counts, percentiles, fake opponent records) replaced with real fields or dropped.
- Drift fixes to match spec: ZOver continue price = `GameConstants.continueCostCoins` (25, not 50); Daily turn timer = 15s (not 10s).

**Out-of-scope fixes made during Phase 17** (bugs in "Complete" phases, user-approved): Persian-rejecting `^[a-z]+$` word regex in `GameBloc` (→ `DictionaryService.hasValidChars()`); `StatsDao.recordGameResult` never updating `bestMatchStreak`; five multiplayer contract bugs that made 1v1 non-functional (queue long-poll timeout, match-found signal, WS route behind header auth, `game_start` parsing, byte-vs-rune next letter); AI opponent's non-UUID id (→ `SystemAIUserID`, migration `004_ai_system_user`); daily challenge auto-generation scheduler job; `fa.txt` cleanup (162,626 → 17,414 words).

**Done when:** All screens render pixel-close to the design in both light and dark mode and are verified on-device, no screen file references a hardcoded color, existing golden tests are re-baselined, and placeholder features (rounds, multiplayer lives, levels/badges, typing indicator) have tracked backend follow-up tickets.

---

## Phase 18 — Bug Fixes & Quick Wins
**Status: [ ] Not Started**

> Planned 2026-09-28. Pre-existing bugs found during Phase 17 plus the cheapest placeholder features. Product decisions below were made by Claude on the user's instruction ("make the best decision yourself") — revise here if the product owner disagrees.

**Scope:**
- ~~**Time Attack fix**~~ — moot: Time Attack was removed from the app entirely on 2026-10-03.
- **FCM permission** — `NotificationService.requestPermission()` has no call site. Call it once after the first completed game **or** first successful login (whichever comes first), persisting `notif_permission_asked` in `shared_preferences`; register the token on grant.
- **Long-word bonus in Go** — `engine.CalculateScore` doubles the turn score for words ≥ `config.LongWordBonusMinLength` (7), matching Flutter's `GameConstants`. Unit tests.
- **Typing indicator** — new WS events: client → `{ "type": "typing" }` (sent at most once per 2s while the input is non-empty and it's my turn); server → `{ "type": "opponent_typing" }` relayed to the other player only, dropped if not the sender's turn. ZVersus turn banner shows «[نام] دارد می‌نویسد…» for 3s after the last event.
- **Leaderboard today / all-time tabs** — *Decision: same sources as weekly (multiplayer + Daily Challenge only, never solo).* `AddScore` also writes `leaderboard:global:daily:{YYYY-MM-DD}` (TTL 48h) and `leaderboard:global:alltime` (never reset). `GET /leaderboard?type=global|friends&period=weekly|daily|alltime` (default `weekly`). ZBoard restores the canvas's 4 tabs: این هفته / امروز / همیشه / دوستان (friends stays weekly).

- **ZProfile cosmetic settings** — persist «صدا و لرزش» locally (`shared_preferences`) and wire «یادآور چالش روزانه» to a local notification at the chosen time; give ZHome's bell a destination (pending friend requests/challenges).

> Already done ahead of this phase (2026-09-28): stale WS/engine test fixtures rewritten in Persian; rarity bonus removed with the English frequency list; Go scorer and multiplayer AI made rune-based; Persian AI trap letters.

**Done when:** all Go + Flutter tests green; the permission prompt appears once; ZBoard shows 4 tabs with real data.

---

## Phase 19 — Multiplayer Lives & Best-of-5 Rounds
**Status: [ ] Not Started**

> Both change the WS room's end-of-turn logic, so they ship together. Decisions by Claude (see Phase 18 note).

**Decisions:**
- **Lives**: each player has `config.MultiplayerLives = 2` per round. An invalid word or timeout costs a life and **passes the turn to the opponent** (same required letter — the chain is unchanged). Losing the last life is a round loss.
- **Shield** is consumed before a life. **Continue** is offered only when the last life is lost (once per player per match, as today) and restores 1 life.
- **Rounds**: best of `config.MultiplayerRoundsTotal = 5` — first to 3 round wins takes the match. Each round starts a fresh chain and resets lives; the round loser starts the next round. Round scores accumulate; the match winner is decided by round wins, not score.

**Scope:**
- `internal/ws/room.go` — per-player lives, round state (`round`, `roundWins`), round transition.
- WS protocol additions: `word_rejected` gains `lives_remaining`; new `life_lost { player_id, lives_remaining, reason }`, `round_over { winner, round, round_wins }`, `round_start { round, starting_player, start_letter? }`. `loss_event` now means "lost the last life". Update CLAUDE.md § WebSocket Event Protocol.
- Migration `005_match_rounds` — `match_players.round_wins SMALLINT DEFAULT 0`.
- Flutter: `GameBloc` WS handlers for the new events; ZVersus shows the «۲ جان» chip and a live «دست N از ۵»; a short between-rounds interstitial (derived from the token system).
- WS tests for: life loss → turn passes, shield-before-life, continue restores a life, 3 round wins end the match.

**Done when:** a real 1v1 (and AI-fallback) match plays through multiple rounds with lives on-device; all WS tests pass.

---

## Phase 20 — Progression & Lobby Economy
**Status: [ ] Not Started**

> Decisions by Claude (see Phase 18 note).

**Levels & XP** — *Decision:* XP earned = final match score ÷ 10 (rounded down), all modes including solo (solo XP arrives via the existing `POST /game/solo` sync). Level L needs `100 × L` XP to reach L+1 (config constant). Migration adds `player_stats.xp`, `player_stats.level`. `GET /profile/stats` returns `xp`, `level`, `xp_to_next`. ZProfile `_LevelCard` wired. Level titles (e.g. «واژه‌باز») from a small client-side table keyed by level range.

**Badges** — *Decision:* start with 12 server-defined badges (first win, 10/100 wins, streak 3/7/30 days, 7+-letter word, 20-word chain, perfect Daily (20 words), 5 friends, first referral redeemed, level 10). Table `player_badges(user_id, badge_id, earned_at)`; evaluated at game end and on the relevant events; `GET /profile/badges`. ZProfile `_BadgesCard` shows «N از ۱۲». Push notification on earn.

**Wager + turn length** — **Superseded 2026-10-03.** Time Attack is gone, the turn is fixed at 15s, and the wager was implemented as a fixed 20-coin **entry fee** (winner takes the pot; AI-fallback matches free; both players' balances pre-checked at queue join and charged at match start). No `turn_sec`/`wager` queue fields and no per-option queues were needed. Remaining here: add the entry-fee rows to the coin-economy table (done in CLAUDE.md) and verify balances on-device for win, loss, draw, cancel and disconnect.

**Join by code** — **Dropped 2026-10-03** (built, then removed by product decision). Friend challenges remain the way to play a friend.

**Done when:** levels/badges work end-to-end with real data; entry-fee coin balances verified on-device after every path (win, loss, draw, cancel, disconnect).

---

## Phase 21 — Production Readiness
**Status: [ ] Not Started**

**Scope:**
- Real `MonetizationService` (AdMob rewarded/interstitial + RevenueCat IAP); backend `ValidateReceipt` performs real store validation (currently always returns nil).
- Kavenegar account + end-to-end SMS/voice OTP verification; remove or env-gate the `1111` bypass for production builds.
- Guest → phone account migration: on first `verify-otp`, the client uploads all unsynced local matches and merges local stats (already mostly covered by `SyncService.sync()` — verify and close the gap noted in CLAUDE.md § Guest Mode).
- Referrer-side reward — *Decision:* +50 coins to the referrer when the referred user completes their first game (not at signup, to deter fake accounts). Push notification to the referrer.
- Full Phase 16 integration smoke flows re-run on real devices.

**Done when:** store builds pass review requirements; no mock services in release builds.
