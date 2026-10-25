# todo.md — backend / WebSocket and follow-ups

Collected 2026-10-17 from the code and from `CLAUDE.md`, `REDESIGN_PLAN.md`, `ADMIN_PLAN.md` and `TODO_FCM_DELIVERY.md`. Every item below was found in the repo (file references given); nothing is speculative. Each line: **what** — files — *why it matters*.

---

## 1. Backend / WebSocket

### 1.1 Leaving an online game does not forfeit it  ✅ DONE 2026-10-17 (not yet verified on two devices)
- **Done:** new WS message `forfeit` (`Room.processForfeit` → `Room.forfeit`, shared with 1.2); `GameBloc._onGameEnded` sends it in multiplayer and shows `GameOver(iWon: false)`. Tests: `backend/internal/ws/forfeit_test.go`, `client/test/features/game/game_bloc_forfeit_test.dart`. The notes below are the original analysis.
- **What the client sends today:** nothing. Tapping «تسلیم و خروج» dispatches `GameEnded`; `_onGameEnded` finalises the game *locally* (`GameOver`, reason `ended_by_user`) and `_saveAndEmitFinal` returns early for multiplayer. No WebSocket message is sent. The socket stays open until the player leaves the result screen (`GameBloc.close()` → `_wsService.disconnect()`).
- **What the server does:** `Room.handleMessage` only knows `submit_word`, `use_powerup`, `continue`, `send_taunt`, `ping`. Until the socket closes the match goes on: turn timers run, a timeout on the leaver's turn opens a continue window. On close, `Room.leave` broadcasts `opponent_disconnected` and starts a 30 s grace; only then `resolveGame(opponent)` runs, settles the entry fee (winner takes the pot) and sends `game_over`.
- **Proposed:** new client message `{ "type": "forfeit" }`. Server: `case "forfeit"` → under `r.mu`, if the room is `stateActive` or `stateContinueWin`, call `resolveGame(r.opponentOf(client.userID))` (same path as a lost continue: `game_over` with `winner`, `scores`, `payout`, DB finalise, `closeAfterDrain`). Client: in `_onGameEnded` when `_isMultiplayer`, send it before finalising locally, and mark the local `GameOver` `iWon: false`. Document it in the WS protocol section of `CLAUDE.md`. Add a room test (forfeit by the player to move, and by the waiting player; fee settled once).
- **Files:** `client/lib/features/game/bloc/game_bloc.dart` (`_onGameEnded` ~l.781, `close()`), `client/lib/features/game/view/widgets/z_exit_confirm.dart`, `backend/internal/ws/room.go` (`handleMessage` ~l.358, `leave` ~l.303, `resolveGame` ~l.949).
- **Why:** the exit dialog promises «می‌بازی»; today the opponent keeps playing against an absent player until the socket closes + 30 s, and the leaver can sit on the result screen with the match still live.

### 1.2 `continue` with `method: "forfeit"` is silently dropped  ✅ DONE 2026-10-17
- **Done:** `processContinue` handles `"forfeit"` (broadcasts `continue_decision` forfeit, resolves for the opponent; the window timer is invalidated by `resolveGame`). Original analysis below.
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
- **Why:** ZVersus deliberately shows no «۷ حرف · دوبرابر» tag (the server does not apply it); add the tag back when this lands.

### 1.6 Typing indicator
- **What:** no WS event for «… دارد می‌نویسد»; ZVersus ships without it.
- **Files:** `backend/internal/ws/room.go` (`inMsg`/`outMsg`), `client/lib/features/game/view/z_versus_screen.dart`.

### 1.6a Opponent name is not in `game_start`  (client falls back to «حریف»)
- **What is sent today** (`gameStartState`, `backend/internal/ws/room.go` ~l.68, built in `startGame` and `sendCurrentState`): `match_id`, `mode`, `players` (user IDs only), `current_turn`, `chain`, `scores`, `next_letter`, `entry_fee`, `premium` (IDs with an active subscription) and `avatars` (userID → premium avatar ID, only for players who have one). So the opponent's **premium flag and avatar are already sent** and the client uses them (ZVersus pill crown + discs, in-chain bubbles, ZOver head-to-head). **No usernames** — not on `game_start`, nor on any other WS message.
- **Needed:** `usernames` on `game_start.state`: `{ "<userID>": "<username>", … }` for both players.
- **Where:** add `Usernames map[string]string \`json:"usernames,omitempty"\`` to `gameStartState`; fill it in `startGame` and `sendCurrentState` next to `perkState()` (a `usernameState()` modelled on `perkState()`, which already does a 3 s-timeout DB lookup while `r.mu` is held); give `RoomDeps` a `Usernames` lookup (the `UserRepository.GetUsernames(ctx, ids)` that `LeaderboardService` already uses fits) wired in `backend/cmd/server/main.go` beside `Perks: userRepo`. Decide what the AI-fallback user (`config.SystemAIUserID`) reports (its seeded username, or omit and let the client keep «حریف»).
- **Client when it lands:** parse it in `GameBloc._handleWsGameStart` into `opponentUsername` (everything already reads `state.opponentUsername ?? 'حریف'`), copy it into `GameOver` so ZOver's «مقابل حریف» / the disc initial «ح» can use it (`ZOverVersusPill`), and drop the `usernames` absence test in `game_bloc_taunt_test.dart`.
- **Why:** both players see «حریف» / «ح» for each other today, even though each knows their own name.

### 1.6b Taunt rejection signals
- **What the server does:** `Room.processTaunt` answers the sender with `taunt_rejected` (`premium_required` | `rate_limited`). The client shows a toast («هر ۵ ثانیه یک طعنه · تا ۸ طعنه در هر بازی» for `rate_limited`, «این امکان فقط برای اشتراک ویژه فعال است» for `premium_required`). Two gaps: `rate_limited` covers both the 5 s cooldown and the 8-per-match cap, so the client cannot say which one applied (state the rule, not the cause); and an unknown taunt id, or a taunt sent outside an active match, is dropped **without** any reply.
- **Optional fix:** split `rate_limited` into `cooldown` / `taunt_cap`, and add `unknown_taunt`; `outMsg.Reason` already carries free-form reasons. Not blocking.
- **Files:** `backend/internal/ws/room.go` (`processTaunt` ~l.565), `client/lib/features/game/bloc/game_bloc.dart` (`_handleWsTauntRejected`).

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
- **What:** no endpoint reports players online; ZHome shows «۳٬۴۰۱ نفر آنلاین» in debug builds only (`kDebugMode`, marked `PLACEHOLDER`). `Hub.Snapshot()` already counts live players for the admin dashboard. The ZLobby canvas (`ZLobbyA`) also has a «۳٬۴۰۱ نفر آنلاین · هم‌سطح تو» chip under the mascot — omitted for the same reason, and its «هم‌سطح تو» half is false today: `MatchmakingService.processQueue` pairs the first two fresh queue entries by arrival order (no level/score matching).
- **Request (if wanted):** `GET /api/v1/match/online` → `{ "data": { "online": 3401, "searching": 2 } }` (auth required, cache 5–10 s) — add a handler next to `MatchmakingHandler` (`backend/internal/handler/`), fill it from `Hub.Snapshot()` (players in rooms) and the Redis queue length (`LLEN queue:classic`); client: `LobbyRepository.fetchOnline()` + a chip in `LobbyStage`'s slot under the mascot (it currently only holds the elapsed-time chip while searching). Only add «هم‌سطح» if pairing actually uses level.
- **Files:** `client/lib/features/home/view/home_screen.dart`, `client/lib/features/lobby/view/widgets/lobby_stage.dart`, `backend/internal/service/admin_dashboard.go`, `backend/internal/service/matchmaking.go`.

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
- **What the server sends today (checked 2026-10-25 in `handler/friends.go`, `service/leaderboard.go`):** `GET /friends` → `user_id`, `username`, `friend_since` (the client ignores `friend_since`). `GET /friends/requests` → `requester_id`, `username`, `requested_at`. The friends leaderboard row (`GET /leaderboard?type=friends`, already fetched for the weekly score) carries `avatar_id` while the friend's premium is active — the Friends tab now shows it. **Still missing:** presence (online/offline, in-match status), per-friend head-to-head record («با هم: ۴ برد · ۲ باخت»), best chain («بهترین زنجیر ۲۹»), mutual-friend count («۳ دوست مشترک»), a premium flag (a premium friend with no avatar picked looks free), whether a request came through the player's invite code («با کد دعوت تو آمده»). The ZFriendsA / ZLobbyA canvases draw all of these; the app shows the weekly score instead and omits the rest.
- **Request (if wanted):** add `avatar_id` + `premium` + `last_seen_at` (or an `online` bool from `Hub`) to `friendResponse` in `backend/internal/handler/friends.go` (fill from `UserRepository.GetPerks(ctx, ids)` like `LeaderboardService.attachAvatars`; presence from `Hub.Snapshot()`), `mutual_friends` + `via_referral` to `pendingRequestResponse`, and a `GET /friends/:id/record` → `{ wins, losses, best_chain }` (new query over `match_players` joined on both user ids). Client: `FriendModel` / `PendingRequest` fields and the two sub-lines in `friends_list_card.dart` / `friends_requests_card.dart`; the lobby card (`lobby_friends.dart`) can reuse the avatar the same way (it still shows initials only).
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

### 2.13 Leaderboard data gaps (found in the ZBoard rebuild, 2026-10-25)
- **`type=friends` answers with the global weekly rank.** `handler/leaderboard.go` special-cases only `alltime`; for `friends` it returns `player_rank` / `player_score` from `GetPlayerRank` (the Redis rank on the *whole* weekly board), not the player's place among friends. The client now ignores them for that tab and reads the place from the entries (`LeaderboardRepository.fetchFriends`), so nothing is broken — but the field is misleading. **Fix:** in `Get`, for `lbType == "friends"` take the rank/score of the requester's entry in `entries` (it always contains them), or add `friend_rank`; then drop the client workaround.
- **Daily board rows have no `avatar_id`, and the response has no player score.** `handler/daily.go` `dailyBoardEntry` = `rank, user_id, username, score, chain_length`; the envelope has `my_rank` only. So daily rows show initials (premium avatars appear on the other three tabs), and a player below the top 100 sees their rank but no score. **Request:** add `avatar_id` per row (fill with `UserRepository.GetPerks` like `LeaderboardService.attachAvatars`) and `my_score` next to `my_rank` (`DailyService.Leaderboard` already has `GetUserRank`; a score lookup beside it). Client: `LeaderboardRepository.fetchDaily` + `board_rows.dart`.
- **No chain length on the weekly / all-time / friends boards**, so the canvas's «بلندترین زنجیر: N» sub-line exists on the daily tab only. Would need a per-user best-chain field (`player_stats.longest_word` exists, a chain length does not) — only if wanted.
- **Premium flag on board rows** (a crown beside premium players): not sent, only `avatar_id` (and only once an avatar is picked). Same request as 2.6's premium flag.
- **Player count / rank deltas / leagues** (canvas had none of them as real data, none drawn): no endpoint reports «N بازیکن این هفته»; `GetTopN` could return a `total` (`ZCARD`), and last week's rank would need a snapshot kept at `RunWeeklyReset`. Not requested unless the product wants them.

---

## 3. Frontend follow-ups (non-visual)

- **Leaving the lobby while searching doesn't leave the queue** — `LobbyCubit.close()` only cancels its timers/push subscription; the in-flight `POST /match/queue` is not cancelled and `cancelQueue` is only called from the «لغو جست‌وجو» button. Backing out (or the OS killing the route) leaves the player in the server queue until it pairs (they would land in a room nobody is in, then wait up to `RoomWaitTimeoutSec`) or the 35 s long-poll times out. Fix: call `cancelQueue()` from the back button / `close()` when `state is LobbySearching`. — `client/lib/features/lobby/cubit/lobby_cubit.dart`, `lobby_screen.dart` — *flagged during the ZLobby rebuild, behaviour left as it was.*
- **Lobby: invite has no confirm step and can't be withdrawn** — the lobby's «دعوت به بازی» sends at once (the Friends tab asks first via `showFriendChallengeDialog`), and the server happily creates a second pending challenge + push for the same friend (`ChallengeService.CreateChallenge` has no duplicate check). The lobby now blocks a repeat from the same screen visit only. Decide: confirm dialog in the lobby too, and/or a server-side "one pending challenge per pair" rule (+ the withdraw call from 2.1). — `client/lib/features/lobby/cubit/lobby_players_cubit.dart`, `backend/internal/service/challenge.go`.
- **Friends: remove-friend is a long press** — `FriendsCubit.removeFriend` / `DELETE /friends/:id` existed but no screen ever called them; the canvas has no remove control. The Friends tab now opens a confirm dialog on a long press of a row (plus a TalkBack/VoiceOver custom action) and a one-line hint under the list says so. Decide whether to add a visible control (a row menu) or keep it. — `client/lib/features/friends/view/widgets/friends_list_card.dart`.
- **Friends: «دعوت شد» is a 5-minute UI debounce** (`GameConstants.friendInviteSentSec`, kept in `FriendsCubit`, lost on app restart). The server has no «challenges I sent» read, no cancel (2.1) and no duplicate guard, so the app can't know a friend declined or already answered. With `GET /challenges/sent` (+ the withdraw call from 2.1) the label could follow the real state and tapping it could withdraw, as the canvas intends. — `client/lib/features/friends/cubit/friends_cubit.dart`, `backend/internal/service/challenge.go`.
- **Invite code appears twice** — the Friends tab (`FriendsInviteCard`, canvas) and ZProfile's `_InviteCard` both load `GET /referral/me` and share it. Keep both, or point Profile at the Friends tab. Redeeming a code (`ReferralBottomSheet`) is untouched. — `client/lib/features/profile/view/z_profile_screen.dart`.
- **`ZRibbonTitle` default is full width** (the lobby's look); `expand: false` gives the canvas's compact ribbon (Friends). Check ZLobbyA's header against the canvas and flip the default if the lobby ribbon should hug its text too (lobby goldens would change). — `client/lib/core/widgets/z_ribbon_title.dart`.
- **Soft keyboard is dismissed on every AI turn** — `ZWordInput` swaps the `TextField` for the "thinking" card, so focus is lost. Keep the field mounted/disabled or re-request focus when `isMyTurn` flips back. — `client/lib/features/game/view/widgets/z_game_shared.dart` — *player must re-tap the field every turn.*
- **Pre-filled start letter** — the canvas draws the letter pre-filled and the player types the rest; today the whole word is typed. Changes `WordSubmitted` / hint behaviour. — `client/lib/features/game/view/z_solo_screen.dart`, `z_play_screen.dart`, `GameBloc`.
- ~~Board tabs «امروز» / «همیشه»~~ — done 2026-10-25: all four canvas tabs ship (weekly, daily from `GET /daily/leaderboard`, all-time, friends; see REDESIGN_PLAN.md § ZBoard). Left from it: `BoardNote`'s countdown is computed on build, not ticking; `/daily/board` (`DailyBoardScreen`) is an older second render of the daily board.
- **Friends tab badge can go stale** — `MessagesCubit.refresh()` only runs on Home init/resume and on the Messages screen; handling a request on the Friends tab does not refresh it. — `client/lib/features/messages/cubit/messages_cubit.dart`.
- **ZProfile «صدا و لرزش» and «یادآور چالش روزانه» are cosmetic** — nothing persisted, no reminder scheduled. — `client/lib/features/profile/view/z_profile_screen.dart`.
- **Mascot moods** — `HomeMascot` `cheer` / `sad` are never set; the standing `ZMascot` is only used by dialogs so far. — `client/lib/features/home/view/widgets/home_mascot.dart`.
- ~~ZVersus should adopt the shared game frame~~ — done 2026-10-17 (see REDESIGN_PLAN.md § ZVersus). Left from it: the taunt tray is a centred `showZDialog` card, not the canvas's bottom-anchored tray (a `ZTray` is still to be built); `ZBackButton` (legacy 34px) is still used by Daily only (ZLobby moved to `ZGameBackButton` 2026-10-25).
- **Shared widgets still to build** — `ZTray` for the remaining bottom sheets (referral, edit username, avatar picker, buy coins, taunt tray). Done in the ZFriends session (2026-10-25): `ZEmptyState` and `ZLoadState` (loading + failed load, `core/widgets/`), `ZInviteButton` (hoisted from the lobby). **Still to migrate to `ZLoadState`/`ZEmptyState` (not done; the Friends and Board tabs use them):** `_ErrorView` in `daily_screen.dart` and `z_profile_screen.dart` (the board's `_ErrorState` is gone, 2026-10-25), and the bare spinners in `messages_screen.dart`, `rewards_screen.dart`, `daily_board_screen.dart`, `z_profile_screen.dart`, `daily_screen.dart`. — `REDESIGN_PLAN.md` § ZFriends.

---

## 4. Product decisions pending

- **ZVersus follow-ups (2026-10-17):** the 1v1 opponent's name is not in the WS `game_start` state — see 1.6a (backend change request); until then the pill, chip, bubbles and ZOver say «حریف» / «ح». The taunt shows only the latest taunt, inline in the chain under the sender's last word for 3 s (the canvas keeps taunts in the chain history — that needs the bloc to record them; a taunt sent before its sender has played goes under the newest word, or right after the start chip on an empty chain); the «ارسال شد / طعنهٔ این دست» used-state of the taunt button is not built (cooldown/cap are server-side only; rejections are toasted, see 1.6b). — `client/lib/features/game/view/z_versus_screen.dart`, `REDESIGN_PLAN.md` § ZVersus.

- **ZOver follow-ups (2026-10-17):** solo / vs-AI «ادامه با ۲۵ سکه» spends the local `MockMonetizationService` balance, not the server coins / `AuthCubit` (the new HUD coin pill therefore doesn't move); a 1v1 result has no opponent name (`GameOver` carries none — add it from the WS state to replace «مقابل حریف»); the win screen's level-progress bar was dropped (needs fresh stats after the XP credit); no rematch exists (1v1 «حریف جدید» goes to the lobby). — `client/lib/features/game/view/z_over_screen.dart`, `REDESIGN_PLAN.md` § ZOver.
- **vs-AI has no win/loss.** The server stores every solo/AI upload with `winner = player` (`CreateSoloGame`), local `wins` is never incremented for AI, ZOver says «بازی را پایان دادی» on exit. Decide whether an AI result counts as win/loss, then change stats and the exit-dialog copy. — `backend/internal/service/game.go`, `client/lib/core/database/daos/stats_dao.dart`.
- **Taunt limits** — resolved for now: the tray's sub-line states the real rule («هر ۵ ثانیه یک طعنه · تا ۸ طعنه در هر بازی», from `GameConstants.tauntCooldownSec/tauntMaxPerMatch`, mirroring `config.TauntCooldownSec/TauntMaxPerMatch`). Revisit only if rounds (1.4) are built. The tray's «با اشتراک ویژه طعنه بفرست» button is not built: there is no purchase flow (2.7), free players get an explanatory line instead.
- **Multiplayer lives / grace** — build it (protocol change, 1.3) or keep the canvas «۲ جان» chip out for good.
- **Best-of-5** — build it (1.4) or drop the round UI from the design.
- **Daily clock on the exit dialog** — solo/vs-AI pause while the dialog is open, daily and online do not (daily is ranked and prized). Confirm or flip `zExitPausesClock`. — `client/lib/features/game/view/widgets/z_exit_confirm.dart`.
- **Daily on the weekly / all-time boards** — count it or not (2.4).
- **Inbox and rewards icons** were removed from Home (no slot in the canvas); `/messages` has no entry point from Home, rewards are reachable through the chest. Decide whether to add one back. — `client/lib/core/router/app_router.dart`, `home_screen.dart`.
- **Level-chest rewards** — what the chest/crown at levels ۱۳–۱۵ should give (2.3).
- **Online player count** — build the endpoint or keep the real line «با بازیکنان دیگر به رقابت بپرداز» (2.2).
