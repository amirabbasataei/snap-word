# todo.md — backend / WebSocket and follow-ups

Collected 2026-10-17 from the code and from `CLAUDE.md`, `REDESIGN_PLAN.md`, `ADMIN_PLAN.md` and `TODO_FCM_DELIVERY.md`. Every item below was found in the repo (file references given); nothing is speculative. Each line: **what** — files — *why it matters*.

---

## 1. Backend / WebSocket

### 1.1 Leaving an online game does not forfeit it  ⟵ start here
- **What the client sends today:** nothing. Tapping «تسلیم و خروج» dispatches `GameEnded`; `_onGameEnded` finalises the game *locally* (`GameOver`, reason `ended_by_user`) and `_saveAndEmitFinal` returns early for multiplayer. No WebSocket message is sent. The socket stays open until the player leaves the result screen (`GameBloc.close()` → `_wsService.disconnect()`).
- **What the server does:** `Room.handleMessage` only knows `submit_word`, `use_powerup`, `continue`, `send_taunt`, `ping`. Until the socket closes the match goes on: turn timers run, a timeout on the leaver's turn opens a continue window. On close, `Room.leave` broadcasts `opponent_disconnected` and starts a 30 s grace; only then `resolveGame(opponent)` runs, settles the entry fee (winner takes the pot) and sends `game_over`.
- **Proposed:** new client message `{ "type": "forfeit" }`. Server: `case "forfeit"` → under `r.mu`, if the room is `stateActive` or `stateContinueWin`, call `resolveGame(r.opponentOf(client.userID))` (same path as a lost continue: `game_over` with `winner`, `scores`, `payout`, DB finalise, `closeAfterDrain`). Client: in `_onGameEnded` when `_isMultiplayer`, send it before finalising locally, and mark the local `GameOver` `iWon: false`. Document it in the WS protocol section of `CLAUDE.md`. Add a room test (forfeit by the player to move, and by the waiting player; fee settled once).
- **Files:** `client/lib/features/game/bloc/game_bloc.dart` (`_onGameEnded` ~l.781, `close()`), `client/lib/features/game/view/widgets/z_exit_confirm.dart`, `backend/internal/ws/room.go` (`handleMessage` ~l.358, `leave` ~l.303, `resolveGame` ~l.949).
- **Why:** the exit dialog promises «می‌بازی»; today the opponent keeps playing against an absent player until the socket closes + 30 s, and the leaver can sit on the result screen with the match still live.

### 1.2 `continue` with `method: "forfeit"` is silently dropped
- **What:** `AcceptDefeat` sends `{type:"continue", method:"forfeit"}` (`game_bloc.dart` ~l.879) but `Room.processContinue` returns early for anything except `"ad"` / `"coins"`. Declining the continue therefore never reaches the server; the loss only stands when the 15 s continue window times out (`triggerContinueTimeout`).
- **Fix:** handle `"forfeit"` in `processContinue` (resolve the game for the opponent immediately) — same code as 1.1, can share the `forfeit` path.
- **Files:** `backend/internal/ws/room.go` (`processContinue` ~l.652), `client/lib/features/game/bloc/game_bloc.dart`.
- **Why:** the opponent waits up to 15 s for a decision the player has already made.

### 1.3 Multiplayer has no lives / no grace
- **What:** `handleLoss` sends `loss_event` right after a rejected word or a timeout (then a continue window); the WS protocol has no lives. Solo/daily have `GameConstants.soloLives = 2`; ZVersus omits the canvas «۲ جان» chip on purpose.
- **Files:** `backend/internal/ws/room.go` (`handleLoss` ~l.882, `processSubmitWord`), `client/lib/features/game/bloc/game_bloc.dart`.
- **Why:** needs a product decision (see 4) before any protocol work; do not fake it client-side.

### 1.4 Best-of-5 rounds
- **What:** no round state, no `round_won` / `round_transition` events, no match-level winner rule; the server knows one shared chain that ends on the first lost turn. The «دست ۱ از ۵» placeholder was removed from ZVersus.
- **Files:** `backend/internal/ws/room.go`, `REDESIGN_PLAN.md` § Stage 4 / Open Issues.
- **Why:** blocks the canvas's round indicator and the «۳–۲» win screen.

### 1.5 Long-word bonus in the Go scorer
- **What:** words of ≥ 7 letters score ×2 in Flutter solo/AI (`GameBloc._calculateScore`) but not in `engine.CalculateScore`, so multiplayer scores differ from solo.
- **Files:** `backend/internal/engine/scorer.go`, `client/lib/features/game/bloc/game_bloc.dart`, `GameConstants.longWordBonusMinLength`.
- **Why:** ZVersus shows the «۷ حرف · دوبرابر» tag, but the server does not apply it.

### 1.6 Typing indicator
- **What:** no WS event for «… دارد می‌نویسد»; ZVersus ships without it.
- **Files:** `backend/internal/ws/room.go` (`inMsg`/`outMsg`), `client/lib/features/game/view/z_versus_screen.dart`.

### 1.7 A banned player already in a room is not kicked
- **What:** `account_banned` is checked at the WS handshake, queue join and challenge create; a socket already inside a room keeps playing until the next API call. `send-otp` still texts a banned phone.
- **Files:** `backend/internal/ws/`, `backend/internal/service/auth.go`, `CLAUDE.md` § Ban.

### 1.8 Push delivery
- **What:** pushes carry no `data.route` (tapping one only opens the app); the challenger is put into the room by a 2 s poll of `GET /challenges/joinable` (`ChallengeWatcher`), not by a push; iOS needs `GoogleService-Info.plist` + an APNs key.
- **Files:** `backend/internal/service/notification.go`, `client/lib/core/services/challenge_watcher.dart`, `TODO_FCM_DELIVERY.md`.

---

## 2. API / schema

### 2.1 Withdraw a sent challenge
- **What:** `POST /challenges`, `/challenges/:id/respond`, `GET /challenges/pending|joinable` — no cancel endpoint. Canvas 9 says tapping «دعوت شد» again withdraws the invite.
- **Files:** `backend/internal/service/challenge.go`, `backend/internal/handler/`, `CLAUDE.md` § Friend Challenges.

### 2.2 Online player count
- **What:** no endpoint reports players online; ZHome shows «۳٬۴۰۱ نفر آنلاین» in debug builds only (`kDebugMode`, marked `PLACEHOLDER`). `Hub.Snapshot()` already counts live players for the admin dashboard.
- **Files:** `client/lib/features/home/view/home_screen.dart`, `backend/internal/service/admin_dashboard.go`.

### 2.3 Levels, chest, badges, accuracy
- **What:** XP/levels exist (`player_stats.xp`, migration 009, no backfill). Still missing: level-up rewards (the chest/crown milestones ۱۳/۱۴/۱۵ are derived, no reward behind them), badges (no schema; the ZProfile card is commented out), accuracy % and unique-word count.
- **Files:** `backend/internal/config/` (`XPForLevel`), `client/lib/features/home/view/widgets/home_chest.dart`, `client/lib/features/profile/view/z_profile_screen.dart`.
- **Why:** the canvas shows all of it; today the Home chest only reflects unclaimed inbox rewards (`RewardsCubit`).

### 2.4 Daily Challenge scores are not on the weekly / all-time boards
- **What:** `LeaderboardService.AddScore` is called only from `ws.Room` (multiplayer). `CLAUDE.md` § Leaderboard says "multiplayer and Daily Challenge", but its own all-time note says "currently multiplayer only".
- **Files:** `backend/internal/service/leaderboard.go`, `backend/internal/service/game.go` (`CreateSoloGame`), `CLAUDE.md`.
- **Why:** decide, then fix the code or the doc (see 4).

### 2.5 Daily result stats
- **What:** the canvas shows «N نفر امروز بازی کردند · میانگین ۱۲ کلمه» and «بهتر از ۷۸٪»; `DailyChallenge` has no player count / average / percentile, so both are dropped.
- **Files:** `backend/internal/service/daily.go`, `client/lib/features/daily/view/daily_screen.dart`.

### 2.6 Friends list data
- **What:** no presence (online/offline, in-match status); friend rows carry only `userId`, `username`, `weeklyScore`; premium avatar/badge are not on the friends list (they are on leaderboards and ZVersus).
- **Files:** `backend/internal/service/friends.go`, `client/lib/features/friends/data/friends_repository.dart`, `CLAUDE.md` § Premium Perks.

### 2.7 Premium: no billing, no weekly coins
- **What:** `premium_until` is set only by `scripts/grant_premium.sh`; the 200 coins/week grant and an expiry push are not built; `MockMonetizationService.purchase('premium_monthly')` returns success without granting anything.
- **Files:** `backend/internal/service/`, `client/lib/core/services/monetization_service.dart`, `CLAUDE.md` § Premium Perks.

### 2.8 Auth
- **What:** Kavenegar SMS delivery is unverified end-to-end (dev bypass OTP `1111`); guest local data is not migrated into a phone account on signup.
- **Files:** `backend/internal/service/auth.go`, `client/lib/core/services/sync_service.dart`, `CLAUDE.md` § Guest Mode.

### 2.9 Keep the system AI user out of every new query
- **What:** `config.SystemAIUserID` is excluded from the all-time board (`GetAllTimeTop/Rank`), `finalizeToDB`, entry fees, the admin user routes. Any new leaderboard, stats or admin list must exclude it too.
- **Files:** `backend/internal/service/leaderboard.go`, `backend/internal/ws/room.go`, `backend/internal/service/admin_users.go`.

### 2.10 Data clean-up
- **What:** `player_stats.longest_word` and local `longestWord` only grow, so values stored before the "own words only" fix (an AI word) stay until reset by hand; `total_score` counts from migration 008 and XP from 009, no backfill.
- **Files:** `backend/internal/repository/stats.go`, `CLAUDE.md` § Known bugs.

### 2.11 Admin panel A6–A7
- **What:** remaining stages (mandatory TOTP, audit-log viewer, other placeholder pages).
- **Files:** `ADMIN_PLAN.md`, `admin/`, `backend/internal/service/admin_*.go`.

### 2.12 Dictionary licences
- **What:** Hunspell `fa`, Wiktionary and OpenSubtitles licences were not checked.
- **Files:** `backend/internal/engine/data/fa.txt` (byte-identical to `client/assets/words/fa.txt`), `CLAUDE.md` Appendix.
- **Why:** verify before a commercial release.

---

## 3. Frontend follow-ups (non-visual)

- **Soft keyboard is dismissed on every AI turn** — `ZWordInput` swaps the `TextField` for the "thinking" card, so focus is lost. Keep the field mounted/disabled or re-request focus when `isMyTurn` flips back. — `client/lib/features/game/view/widgets/z_game_shared.dart` — *player must re-tap the field every turn.*
- **Pre-filled start letter** — the canvas draws the letter pre-filled and the player types the rest; today the whole word is typed. Changes `WordSubmitted` / hint behaviour. — `client/lib/features/game/view/z_solo_screen.dart`, `z_play_screen.dart`, `GameBloc`.
- **Board tabs «امروز» / «همیشه»** — the client ships 2 of 4 tabs; the backend already has `GET /leaderboard?type=alltime` and `GET /daily/leaderboard`. — `client/lib/features/leaderboard/view/z_board_screen.dart` — *planned in PLAN.md Phase 18.*
- **Friends tab badge can go stale** — `MessagesCubit.refresh()` only runs on Home init/resume and on the Messages screen; handling a request on the Friends tab does not refresh it. — `client/lib/features/messages/cubit/messages_cubit.dart`.
- **ZProfile «صدا و لرزش» and «یادآور چالش روزانه» are cosmetic** — nothing persisted, no reminder scheduled. — `client/lib/features/profile/view/z_profile_screen.dart`.
- **Mascot moods** — `HomeMascot` `cheer` / `sad` are never set; the standing `ZMascot` is only used by dialogs so far. — `client/lib/features/home/view/widgets/home_mascot.dart`.
- **ZVersus should adopt the shared game frame** (`ZBubbleChain`, `ZVersusPill`, `ZGameScaffold`), drop the legacy `ZBackButton`, and get the taunt tray frame. — `client/lib/features/game/view/z_versus_screen.dart`.
- **Shared widgets still to build** — ribbon title, `ZEmptyState`, `ZTray` for the remaining bottom sheets, one shared error/loading state (`_ErrorView` is duplicated in `daily_screen.dart` and `z_profile_screen.dart`). — `REDESIGN_PLAN.md` § Consolidation status.

---

## 4. Product decisions pending

- **ZOver follow-ups (2026-10-17):** solo / vs-AI «ادامه با ۲۵ سکه» spends the local `MockMonetizationService` balance, not the server coins / `AuthCubit` (the new HUD coin pill therefore doesn't move); a 1v1 result has no opponent name (`GameOver` carries none — add it from the WS state to replace «مقابل حریف»); the win screen's level-progress bar was dropped (needs fresh stats after the XP credit); no rematch exists (1v1 «حریف جدید» goes to the lobby). — `client/lib/features/game/view/z_over_screen.dart`, `REDESIGN_PLAN.md` § ZOver.
- **vs-AI has no win/loss.** The server stores every solo/AI upload with `winner = player` (`CreateSoloGame`), local `wins` is never incremented for AI, ZOver says «بازی را پایان دادی» on exit. Decide whether an AI result counts as win/loss, then change stats and the exit-dialog copy. — `backend/internal/service/game.go`, `client/lib/core/database/daos/stats_dao.dart`.
- **Taunt limits** — `config.TauntCooldownSec = 5` and `TauntMaxPerMatch = 8` per player; the canvas copy «یک طعنه در هر دست» assumes rounds, which do not exist. Pick the real rule and the sub-line of the taunt tray. — `backend/internal/config/config.go`, `Room.processTaunt`.
- **Multiplayer lives / grace** — build it (protocol change, 1.3) or keep the canvas «۲ جان» chip out for good.
- **Best-of-5** — build it (1.4) or drop the round UI from the design.
- **Daily clock on the exit dialog** — solo/vs-AI pause while the dialog is open, daily and online do not (daily is ranked and prized). Confirm or flip `zExitPausesClock`. — `client/lib/features/game/view/widgets/z_exit_confirm.dart`.
- **Daily on the weekly / all-time boards** — count it or not (2.4).
- **Inbox and rewards icons** were removed from Home (no slot in the canvas); `/messages` has no entry point from Home, rewards are reachable through the chest. Decide whether to add one back. — `client/lib/core/router/app_router.dart`, `home_screen.dart`.
- **Level-chest rewards** — what the chest/crown at levels ۱۳–۱۵ should give (2.3).
- **Online player count** — build the endpoint or keep the real line «با بازیکنان دیگر به رقابت بپرداز» (2.2).
