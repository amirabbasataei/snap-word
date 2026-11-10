# Scoring & ranking — plan (Phase 25)

> **Status (2026-11-10): S1–S6 done (not deployed — S2–S6 ship together); S7 not started.** One session per stage, in order. Update the status line of each stage (and CLAUDE.md's phase table) when it is done.

## Why

The weekly board («این هفته») and the all-time board («همیشه») add up the **raw word points of every 1v1 game, win or lose** (`ws/room.go` `finalizeToDB` → `LeaderboardService.AddScore`). A loser earns almost as much as the winner (about one word less), so rank measures how much you play, not how well; the weekly top-3 coin prizes go to whoever plays most. Easy-AI fallback games (free, no risk) also count, and two friends can farm each other with friend challenges.

Real competitive games keep two numbers apart: a **skill rating** that moves on wins *and* losses (Elo/Glicko in chess and tournament Scrabble, trophies in Clash Royale) and a **progress score** that only grows (XP). Zanjir keeps the word points for the match score, XP and the Daily Challenge, and adds a rating for ranking.

Two different "streaks" exist — don't mix them up:
- **Daily streak** (`player_stats.daily_streak`): consecutive Iran-time days with a finished game. Correct, not touched by this plan.
- **Match streak** (`r.streaks` in `ws.Room`, `GameActive.streak` in Flutter): consecutive accepted words *inside one game*; it drives the `+50 %` streak bonus of the scoring formula. Per spec it resets on a rejection/timeout — it never does (Stage S1).

## Stages (priority order)

| # | Stage | Size | Depends on |
|---|---|---|---|
| S1 | Scoring bug fixes + remove Freeze | small | — |
| S2 | Rating — backend | medium | S1 |
| S3 | Rating — client + boards | medium | S2 (deploy S2+S3 together) |
| S4 | Anti-abuse & fallback AI by rating | small | S2 |
| S5 | Daily Challenge fairness | medium | S1 |
| S6 | Long-word bonus: smooth it and port to Go | small | S1, S5 |
| S7 | (later, Phase 20) leagues / rating-based matchmaking | large | S2–S4 |

---

### S1 — Scoring bug fixes + remove Freeze
**Status: done 2026-11-10** (code + tests; backend rebuilt locally; **not deployed, not verified on a device**, prod Freeze inventory query not yet run). Outcome:
- Streak: reset at the top of `ws.Room.handleLoss` (the one path for reject *and* timeout, before the shield check), Flutter in both lives branches and in `_consumeShield` (the shield saves the match, not the streak; same rule as Go). The continue already rebuilt `GameActive` with `streak: 0`. Multiplayer's client-side `streak` is display-free and already resets on the opponent's word; the server scores. Tests: `ws/streak_test.go` (reject → continue → no bonus, shield, timeout), `client/test/features/game/game_bloc_streak_test.dart`.
- ZWNJ: `engine.LetterCount` (`engine/scorer.go`) and `GameBloc.letterCount` (the scorer is now public `GameBloc.calculateScore`); the input card's «دوبرابر» cue uses it too. `maxTurnScore` unchanged (comment explains why). **Flagged, not changed:** the ≥2-letter minimum counts ZWNJ in Go `ValidateMove`, Flutter `DictionaryService.isValid` and the bloc's `too_short` check — no `fa.txt` word is affected (none has < 2 real letters); the AI minimum lengths (`engine.SelectAIWord` / `ai_opponent.dart`) count it too, so Hard (min 6) can play 310 words with 5 real letters.
- Freeze: gone from Go (`config.CoinFreeze`, `PowerupPrice`, `freezePending`, `startTurn`) and Flutter (ZVersus list, labels, prices, `canUsePowerup`). Unknown types now get `powerup_rejected` reason `unknown_powerup` before `UseItem` (`TestRoomFreezeRejectedWithoutCharge`); the Flutter handler ignores the reason. The ZVersus freeze test became "three power-ups are offered".
- Goldens: the ZVersus goldens that show the power-up row will differ — they already fail on this Linux box on a clean HEAD (same 9 before and after), so regenerate them on a machine where they pass.
- **Prod (todo before/at deploy):** `SELECT count(*) FROM powerup_inventory WHERE powerup_type='freeze' AND quantity>0` — if any, refund 20 coins each as an `admin_gift` and delete the rows.

1. **Match streak resets on a mistake.**
   - Go `ws.Room`: set `r.streaks[player] = 0` on every rejected word and every timeout (in `processSubmitWord`'s reject branch and `triggerTurnTimeout`, i.e. before `handleLoss`), so it is 0 after a continue *and* after a shield-negated mistake.
   - Flutter `GameBloc`: `streak: 0` in the two lives branches (life lost on an invalid word, life lost on a timeout — `game_bloc.dart` ~337 and ~759) and wherever a continue resumes (already 0 at ~852 — verify).
   - Tests: Go room test (reject → continue → next word has no streak bonus), bloc tests for both lives branches.
2. **Half-space (U+200C) is not a letter.** Today 3,793 words get +10 per ZWNJ and 759 reach the 7-letter ×2 bonus only because of it (e.g. آب‌بازی).
   - Add `engine.LetterCount(word)` (runes minus ZWNJ) and use it in `engine.CalculateScore`; mirror it in Flutter (`letterCount` helper next to `_calculateScore`, used for base score and the long-word check).
   - **Do not tighten the Daily bound yet:** `service.maxTurnScore` must keep counting ZWNJ (the old formula) so a Daily run uploaded by an older app — scored the old way — is not refused with `invalid_daily_chain` (SyncService would then drop it forever). The bound is only an upper limit, so staying lenient is safe; S5 replaces it.
   - Check whether the ≥2-letter minimum (`engine.ValidateMove` / `DictionaryService`) also counts ZWNJ; if so, flag it — it's a validation change, not a scoring one.
3. **Remove the Freeze power-up.** As built it is backwards: the tile says «انجماد حریف» but `room.go` gives the *opponent's* next turn +5 s, so paying 20 coins helps the other player. Nobody can own it (inventory only grows from future rewards), so removal costs no one anything.
   - Go: drop `freeze` from `processUsePowerup`'s allowed list, `freezePending` and its use in `startTurn`, `config.CoinFreeze` and its `PowerupPrice` case. Unknown types are silently ignored today — reply `powerup_rejected` instead so an old app that still shows the tile gets an answer and no coins are charged (the type check runs before `UseItem` — keep it that way).
   - Flutter: remove `'freeze'` from ZVersus' power-up list, labels (`z_game_shared.dart`, `game_bloc.dart` `_powerupName`), `GameConstants.powerupCostCoins`, the bloc's `case 'freeze'`, comments, and the `z_versus_screen_test.dart` freeze test (replace with "three power-ups are offered").
   - Prod: `SELECT count(*) FROM powerup_inventory WHERE powerup_type='freeze' AND quantity>0` — if any, refund 20 coins each as an `admin_gift` and delete the rows.
   - CLAUDE.md: power-up table, WS protocol example (`use_powerup … "freeze"`), the `powerup_inventory` comment.
4. Rebuild the backend, run Go + Flutter tests, update CLAUDE.md § Scoring Formula / Streak rules / Power-ups.

### S2 — Rating backend
**Status: done in code 2026-11-10** (Go + admin panel, tests with real Postgres, backend rebuilt locally, migration 019 applied locally; **not deployed — ships with S3, right after a Saturday reset**; no live 1v1 match was played against it, the REST boards/stats/admin pages were checked live with empty data). Outcome and decisions beyond the plan:
- Name stays «جام» (the S2 request said «ماج», read as a typo). Defaults exactly as below (`config.Rating*`, `WeeklyMinRatedGames`, `WeeklyPrizeScanLimit`).
- `rating_history` has FKs to `matches` (ON DELETE CASCADE) and `users`. A **pair-capped game writes no history row and does not count in `rated_games`**; its `rating_update` carries `reason: "pair_cap"` with every delta 0. Retried applies return the stored rows (`Applied=false`) and feed the weekly board only once; concurrent applies are serialised by the `FOR UPDATE` on both `player_stats` rows (locked in id order).
- WS: picked the **follow-up `rating_update`** event. `resolveGame` now starts `Room.afterGame` (rating → queue `rating_update` → `closeAfterDrain` → `finalizeToDB`); the close moved behind the rating because closing a send channel before the broadcast would panic. A failed rating write sends nothing and still closes the room. `game_start.state.ratings` added (humans only).
- Weekly board: besides `leaderboard:weekly:rating` and `:wins`, a third hash **`leaderboard:weekly:games`** (needed for the ≥5-games prize rule). Order: Δ, wins, user id; `GetTopN` also pulls every member tied with the last fetched one so the wins tie-break is exact at the cut. Prizes go to the first 3 *eligible* players, ranked 1–3 among them. The reset deletes the old `leaderboard:global:weekly` key **unpaid** (cut-over option "deploy right after a Saturday reset"; the option of paying it one last time was not built).
- `GET /leaderboard` keeps its shape and adds `games` (+ `wins` on weekly rows), `player_games` (+ `player_wins` on weekly). On the friends board `player_rank` is now the caller's place **among friends** (was their global weekly rank, todo.md 2.13). The all-time `player_score` is the caller's rating even below 10 games (rank 0).
- `/profile/stats` also returns **`total_score`**: the all-time board no longer carries word points, and S3 shows «مجموع امتیاز» from here.
- Removed the dead word-points queries (`LeaderboardRepository.GetAllTimeTop/GetAllTimeRank`); `LeaderboardUpdater.AddScore` → `AddTotalScore`.
- Admin panel: user page «جام» row, match detail «جام ±N ← after» per player (`rating_before/after/delta`, null when unrated), «جدول امتیازات» shows weekly Δ / wins / rated games and the all-time rating.
- Tests: `service/rating_test.go` (Elo table, K switch, floor, apply, replay, concurrent apply, pair cap incl. the next Iran day, draw/AI), `service/leaderboard_rating_test.go` (weekly order/tie-break/standing, reset eligibility + idempotency + key cleanup, all-time min games/banned/AI, friends), `ws/rating_test.go` (`rating_update` after `game_over` with deltas, one apply per match, pair cap, draw/AI/cancelled unrated, failure still closes), an admin-matches detail case, panel tests.
- **Until S3 ships, the current app would show ratings under the old word-points labels** — hence S2 must not be deployed alone.

**Decided defaults** (change them before starting S2 if you disagree):
- **Elo**, shown to players as «جام». Start 1000, floor 0. `E = 1 / (1 + 10^((Rb − Ra)/400))`, `Δ = round(K × (S − E))`, S = 1 win / 0 loss. K = 32 for a player's first 30 rated games, then 16. Both players' deltas are computed from the pre-match ratings.
- **Rated:** 1v1 human vs human, from the queue *and* friend challenges. **Not rated:** AI-fallback rooms, cancelled rooms (`match_cancelled`), draws (`winnerID == ""` — no change).
- Forfeit, declined continue and disconnect-timeout are losses (they already resolve with a winner).
- **Pair cap:** only the first 3 rated games per pair of players per Iran day count; later ones are played normally but change nothing (stops win-trading between two accounts).

Work:
1. Migration `019_rating`: `player_stats.rating INT NOT NULL DEFAULT 1000`, `rated_games INT NOT NULL DEFAULT 0`, `peak_rating INT NOT NULL DEFAULT 1000`; table `rating_history (match_id UUID, user_id UUID, opponent_id UUID, rating_before INT, rating_after INT, delta INT, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (match_id, user_id))` + index `(user_id, created_at)` (pair-cap lookup and profile history).
2. `service.RatingService.ApplyMatchResult(ctx, matchID, winnerID, loserID)` → `repository.RatingRepository`: one transaction, `SELECT … FOR UPDATE` both rows, pair-cap check, insert both history rows (the primary key makes a retry a no-op), update ratings. Pure Elo math in its own function with table tests.
3. Wire into `ws.Room.finalizeToDB` (new `RoomDeps.Rating` interface); skip rooms with the AI user. Send the result back: `game_over` gains `rating: {"<userId>": {"before", "after", "delta"}}` — compute it *before* broadcasting (currently the DB work runs after `game_over`, so `resolveGame` must call the rating step first or send a follow-up `rating_update` event; pick the follow-up event if moving DB work under the room lock is a problem).
4. **Boards:**
   - Weekly: new Redis key `leaderboard:weekly:rating`, `ZINCRBY delta` (negative allowed) for each rated game, plus a hash `leaderboard:weekly:wins` for tie-breaks. Prize-eligible: net Δ > 0 and ≥ 5 rated games that week (`config.WeeklyMinRatedGames`). `RunWeeklyReset` reads the new key.
   - All-time: `ORDER BY rating DESC` from `player_stats`, only players with `rated_games ≥ 10` (`config.RatingMinGamesForBoard`), banned + AI excluded as today.
   - Friends: friends ordered by rating.
   - `GET /leaderboard` keeps its shape (`score` = weekly Δ or rating); add `wins` to weekly rows.
   - Stop writing the old `leaderboard:global:weekly` key. Keep `player_stats.total_score` growing (it becomes a profile stat, «مجموع امتیاز»); rename `AddScore` → `AddTotalScore` usage accordingly.
5. `GET /profile/stats` adds `rating`, `rated_games`, `peak_rating`. `game_start.state` adds both players' ratings (optional, nice for ZVersus).
6. **Cut-over:** deploy just after a Saturday reset (the old key's week has been paid), or let the next reset pay the old key one last time and switch afterwards. Everyone starts at 1000 — no backfill.
7. Admin panel: show rating on the user page and the matches detail (Δ per player). Read-only.
8. Tests: Elo math, pair cap, idempotent apply, draw/AI/cancel unrated, weekly eligibility, board SQL (real Postgres), room integration (game_over carries the deltas).

### S3 — Rating client + boards
**Status: done 2026-11-10** (client code, tests, and a live check on two Android emulators against the local backend; **not deployed — deploy S2 + S3 together right after a Saturday reset, ask before doing it**). Outcome and decisions beyond the plan:
- **ZOver:** `ZOverRatingCard` under the result in both the win and the loss body, 1v1 only. Delta chip teal / coral beside «جام تو <total>» and «قبلاً <before>». `rating_update` arrives *after* `game_over`, so `GameBloc` handles it on top of the `GameOver` that is already up (`GameOver.rating`, `ratingPairCap`); an update arriving outside a result screen is ignored. `game_start.state.ratings` also tells the client when the opponent is the AI fallback (opponent absent from a map that holds mine → `opponentIsAi`), which is what the «بازی با هوش مصنوعی جام نداره» note keys on (the WS result carries no `opponentType` for the fallback). **Interpretation:** the S3 request text was garbled around the pair-cap case; read as «a rated game that no longer counts» → neutral «۰» chip + «امروز ۳ بار با این حریف بازی کردی. بازی‌های بعدیِ امروز جام نداره.» Change the copy if something else was meant.
- **ZBoard:** weekly = signed net جام + «N بازی · M برد» sub-line; all-time/friends = rating + «N بازی»; Daily unchanged. Prize rule in the weekly note and in the self row (what is still missing). All-time provisional state for < 10 rated games (rating shown, «بعد از ۱۰ بازی رتبه می‌گیری …»). `fetchFriends` no longer re-derives the rank from the entries (S2 fixed `player_rank`).
- **ZProfile:** `ProfileRatingCard` (rating, best, rated games, «مجموع امتیاز» from `total_score`), signed-in only. **ZVersus:** rating after «تو» / «حریف» in the pill (the AI fallback and old servers show names only).
- **Tests:** `game_bloc_rating_test.dart` (game_start ratings, AI detection, rating_update incl. pair cap / foreign / malformed / outside a result), `z_over_screen_test.dart` «جام» group (+ layout cases, + 2 new goldens `z_over_win_rating_light`, `z_over_loss_rating_dark`), `z_board_screen_test.dart` + repository/cubit tests updated, ZVersus pill, ZProfile card. Regenerated goldens: the five ZBoard ones (`empty light`, `friends dark`, `weekly light/dark/320 dark`) and `z_profile_free_light` / `z_profile_premium_dark`. **Not regenerated:** goldens that already fail on this Linux box on a clean HEAD (z_over win/loss-final/record, ZVersus, buy-coins, daily, `z_profile_lower_half_dark_320`, …) — the set of failing tests is identical before and after S3 (verified with a stash run of the same files).
- **Live check (emulators 5554 + 5556, local SMS switched off for the run and back on afterwards):** two new accounts, a full 1v1 (one let the turn and the continue window run out): loser «−۱۶ → ۹۸۴», winner «+۱۶ → ۱٬۰۱۶» on ZOver; weekly board «+۱۶» / «−۱۶» with games/wins and the prize hint; all-time and friends boards (empty states); profile rating card; ZVersus pill ratings; then a matchmaking AI-fallback game: pill without the AI's rating, result with the AI note, DB shows only the first game in `rating_history` (2 rows). **Not seen live:** the pair-cap card (unit/widget tested), a board with ≥ 3 ranked players or the all-time provisional self row (widget tested), a rating arriving *late* on a slow link, dark mode.

- ZOver (1v1 only): «+۱۶ جام» / «−۱۲ جام» under the result, new total beside it; nothing for AI fallback («بازی با هوش مصنوعی جام نداره»). Check the canvas first; derive from tokens if there's no design (REDESIGN_PLAN.md rules). *(Canvas checked: no rating frames.)*
- ZBoard: «این هفته» → net جام this week (+ wins); «همیشه» → rating; «دوستان» → friends by rating; «امروز» unchanged (Daily). Update the weekly note text (prize rule: needs ≥ 5 games and a positive week). Empty/provisional state for players with < 10 rated games («بعد از ۱۰ بازی رتبه می‌گیری»).
- ZProfile: rating + peak + rated games; «مجموع امتیاز» stays as a stat.
- ZVersus: opponent rating next to «حریف» if `game_start` sends it.
- All copy in informal Persian per CLAUDE.md; Persian digits; tests assert exact strings; regenerate only the affected goldens.

### S4 — Anti-abuse & fallback AI by rating
**Status: done 2026-11-10** (backend + admin panel; Go and panel tests green, backend rebuilt locally, admin API checked live against the local DB; **not deployed — ships with S2 + S3, ask before doing it**). Decisions beyond the plan:
- **The server ignores any client `difficulty`** on `POST /match/queue` (old apps may still send it; the field is accepted and dropped, `invalid_difficulty` can no longer be returned). The level is read when the fallback fires (not at queue join), from the player's rating: `config.FallbackAILevels` + `service.FallbackAIDifficulty`. A new account (1000) therefore gets **medium**, not easy; a failed rating lookup also falls back to 1000.
- **Test found a leak:** AI-fallback games were still feeding `player_stats.total_score` (the profile's «مجموع امتیاز», documented as lifetime *1v1* points). `ws.Room.finalizeToDB` now skips `AddTotalScore` in AI rooms, so they touch only XP + the daily streak. Tests: `ws/ai_fallback_test.go` (real Postgres; AI game = exactly streak + xp, no rating call; the human-vs-human control also gets `total_score` and the rating).
- **Same-opponent flag:** `GET /admin/users/:id` now returns `same_opponent {flagged, window_days, rated_games, top_games, top_opponent}` from `rating_history` of the last 7 days (pair-capped games write no row, so they are not counted). Flagged = strictly more than 50 % against one opponent **and** at least `config.SameOpponentMinGames` (4) rated games in the window — the minimum is my addition (a single game would otherwise be 100 %). Read-only, no auto-ban, no audit row. Panel: a yellow banner on the user page (with a link to the opponent) and a «بازی با یک حریف» line in the «بازی» card. Both players of a colluding pair get flagged. Tests: `service/same_opponent_test.go`, `admin/src/pages/UserDetail.test.tsx`.

- Fallback AI level chosen **by the server** from the player's rating (< 1000 easy, 1000–1199 medium, ≥ 1200 hard; `config.FallbackAILevels`). Today the client sends no `difficulty`, so it is always easy.
- Confirm AI-fallback games touch only XP + daily streak (no weekly/all-time/rating) — S2 already skips them; add a test.
- Admin: a flag on the user page when > 50 % of a player's rated games in the last 7 days are against the same opponent (read-only signal, no auto-ban).

### S5 — Daily Challenge fairness
**Status: done 2026-11-10** (backend + Flutter + admin panel; Go, Flutter and panel tests green, backend rebuilt locally and checked live over HTTP; Drift schema v3; **not deployed — ships with S2 + S3 + S4, ask before doing it**, **not verified on a device**). Decisions beyond the plan:
- **Formula decision:** implemented **today's ×2 long-word rule** in Go (`engine.CalculateSoloScore`, a mirror of `GameBloc.calculateScore`) and left the swap to S6 (the plan's own S6 text expects S5 to be formula-agnostic). The two sides share one vector table (`engine/scorer_test.go` ↔ `score_trace_test.dart`); S6 must change both scorers, both tables and the Daily recompute together.
- **Streaks are uploaded too** (`word_streaks[]`, the streak before each word), not only `word_times_ms[]`: lives and the shield reset the streak and the chain does not record them, so the server could not recompute otherwise. Validated structurally (first 0; each 0 or previous + 1). No cap on the number of resets: a resumed run restarts at 0 and must stay valid.
- **Extra Time:** instead of a per-word flag, the time ceiling is `(15 + 8) s + 2 s slack` for every word (the speed bonus is already 0 past 15 s, so a long time never helps a cheater); floor 300 ms (`config.DailyWordMinMs`).
- **Resume bug found and fixed on the way:** a resumed solo/Daily match restored `score = 0` (the row only gets its score at game end), which would make every resumed Daily run fail the exact recompute. The per-word trace is persisted per accepted word (`local_matches.score_trace`, Drift v3, real v2→v3 upgrade tested) and the resumed score is rebuilt from it. A pre-v3 / mismatching trace is never uploaded (lenient bound applies) and keeps score 0 as before.
- **Ranking:** `GetDailyLeaderboard`, `GetUserRank`, `GetTodayBest` (hence `RunDailyPayout`, the admin board and `GET /daily`'s `rank` / `today_best`) use `attempt_number = 1`. `your_best` and the result hero still show the better of the two attempts. Retry button / compare card / board note / rules tile / hero pill say that the retry only sets a personal record. The retry still costs 25 coins and is **not** refunded or re-priced — flag if you want the retry rethought now that it buys no rank.
- Not done: an old app keeps the lenient bound until a minimum app version is enforced (then drop the no-trace path); timings remain client-reported.
- Goldens: regenerated `daily_before_*` and `daily_board_*`; `daily_after_*` / `after + retried` fail on this box on a clean HEAD and must be regenerated on a machine where they pass.

- **Prizes and the «امروز» ranking use the free attempt only** (`attempt_number = 1`). A paid retry still records a personal best shown on ZDailyAfter («بهترین تلاشت»), but cannot buy a better prize rank. Touches `DailyRepository.GetDailyLeaderboard` / `GetUserRank`, `RunDailyPayout`, ZDailyAfter/Before copy, the admin daily detail.
- **Recompute the score on the server:** the client also uploads `word_times_ms[]` (one per word) on `POST /game/solo` for `mode: daily`; the server recomputes with the exact Flutter formula (needs `engine` to share the long-word rule — do S6's formula decision first or implement today's ×2 and change it in S6) and rejects a mismatch (`400 invalid_daily_chain`). Plausibility: each time 300 ms … 15 s (+8 s if Extra Time was used — upload a used-power-up flag per word or allow it). Uploads **without** timings (old apps) keep the bound check — the lenient one from S1 — until the minimum app version is raised.
- Timings are still client-reported; this closes the "post the max score" cheat, not a client that fakes its timings.

### S6 — Long-word bonus
**Status: done 2026-11-10 (not deployed — ships with S2–S5; not verified on a device).**

- **Decision:** `long_bonus = max(0, letters − 6) × 15` (`config.LongWordBonusFrom` 6 / `LongWordBonusPerLetter` 15, mirrored by `GameConstants.longWordBonusFrom/PerLetter`), added after the speed and streak bonuses. Simulated against the ×2 rule first: a fast 7-letter word 192 → 111 (a 6-letter one is 86), 9 letters 232 → 161; a six-word chain of 4–5-letter words is unchanged, a mixed chain (4,5,6,7,5,8) 692 → 539, a long chain (7,8,9,7,8,6) 1104 → 729. k=20 was the alternative (554 / 774).
- **One scorer:** `engine.CalculateScore` now includes the bonus (`engine.LongWordBonus`), so multiplayer (`ws.Room`), solo, vs-AI and Daily score the same and XP means the same everywhere. `engine.CalculateSoloScore` and `config.LongWordBonusMinLen/Mult` are deleted; Flutter `GameBloc.calculateScore` / `longWordBonus` mirror it. Vectors (`engine/scorer_test.go` ↔ `score_trace_test.dart`) rewritten with 7-, 9- and 10-letter words and a half-space case.
- **Old apps:** a trace computed with the ×2 rule (app installed before S6) is accepted by `ValidateDailyScore`: it recomputes the whole chain with the new formula, and if that does not match, once with `legacyTurnScore` (same turn score without the flat bonus, doubled from 7 letters, local constants in `service/daily_chain.go`). A mix of the two inside one chain is refused. The no-trace lenient bound `maxTurnScore` takes the larger of the two (always the old ×2 for 7+ letters). Both legacy pieces go once old apps are no longer supported. Cost: during the rollout window an old app's long-word run keeps its higher score on that day's board.
- **UI:** the «رباربود» cue is «کلمهٔ بلند · N امتیاز بیشتر» (N = the typed word's bonus), ZPlay's chip «از حرف ۷، هر حرف ۱۵ امتیاز»; the cue is now shown in ZVersus too (multiplayer has the bonus).
- **Done in the same session (agreed with the owner):** XP is called «تجربه» (level bar, home chip, ZOver chip) instead of «امتیاز»; in a 1v1 loss the «جام» card leads and the word points are a smaller «امتیاز کلمه‌ها» without the opponent's points; «مجموع امتیاز» is gone from the profile rating card; `config.RatingMinGamesForBoard` 10 → 5 (the all-time board then needs the same 5 rated games as the weekly prize).
- **Verified:** `go test ./internal/...` (real Postgres), admin tests, Flutter tests for the touched files (the remaining failures are goldens/tests that already fail on a clean HEAD here; the four goldens that passed on HEAD and changed were regenerated), backend rebuilt and checked over HTTP: a new-formula Daily trace → 201, an old-×2 trace → 201, off-by-one and mixed → 400 `invalid_daily_chain`.

- Replace the ×2 cliff at 7 letters (a fast 7-letter word ≈ 250 points vs ≈ 125 for 6) with a smooth bonus: `long_bonus = max(0, letters − 6) × 15`, added to the turn score (letters via `LetterCount`, S1). Exact numbers are a tuning decision — simulate a few typical chains before choosing.
- Apply it in **both** scorers, so multiplayer, solo, vs-AI and Daily score the same (removes the "Flutter-only" note in CLAUDE.md). XP then means the same in every mode.
- `config.LongWordBonus*` / `GameConstants.longWordBonus*` replaced; the Daily recompute (S5) and its fallback bound accept both the old and the new formula for old apps.

### S7 — Later (Phase 20)
- Duolingo/Scrabble-GO-style weekly leagues: groups of ~30 by rating band, promotion/relegation.
- Rating-based matchmaking: pair within ±150, widening by 50 every 5 s of waiting, before the AI fallback.
- Optional: speed bonus latency grace (measure server RTT from `ping`/`pong`, subtract half of it, capped at 0.5 s). Low value (≈ 1 point/word).

## Not changing
- Daily streak and its milestones.
- Coins for winning (+30) and the entry-fee pot.
- XP stays score-based, losses included — it is a progress score by design.
