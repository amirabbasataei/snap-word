# Scoring & ranking — plan (Phase 25)

> **Status (2026-11-10): planned, nothing built.** One session per stage, in order. Update the status line of each stage (and CLAUDE.md's phase table) when it is done.

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
**Status: not started.**

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
**Status: not started.** Deploy together with S2.

- ZOver (1v1 only): «+۱۶ جام» / «−۱۲ جام» under the result, new total beside it; nothing for AI fallback («بازی با هوش مصنوعی جام نداره»). Check the canvas first; derive from tokens if there's no design (REDESIGN_PLAN.md rules).
- ZBoard: «این هفته» → net جام this week (+ wins); «همیشه» → rating; «دوستان» → friends by rating; «امروز» unchanged (Daily). Update the weekly note text (prize rule: needs ≥ 5 games and a positive week). Empty/provisional state for players with < 10 rated games («بعد از ۱۰ بازی رتبه می‌گیری»).
- ZProfile: rating + peak + rated games; «مجموع امتیاز» stays as a stat.
- ZVersus: opponent rating next to «حریف» if `game_start` sends it.
- All copy in informal Persian per CLAUDE.md; Persian digits; tests assert exact strings; regenerate only the affected goldens.

### S4 — Anti-abuse & fallback AI by rating
**Status: not started.**

- Fallback AI level chosen **by the server** from the player's rating (< 1000 easy, 1000–1199 medium, ≥ 1200 hard; `config.FallbackAILevels`). Today the client sends no `difficulty`, so it is always easy.
- Confirm AI-fallback games touch only XP + daily streak (no weekly/all-time/rating) — S2 already skips them; add a test.
- Admin: a flag on the user page when > 50 % of a player's rated games in the last 7 days are against the same opponent (read-only signal, no auto-ban).

### S5 — Daily Challenge fairness
**Status: not started.**

- **Prizes and the «امروز» ranking use the free attempt only** (`attempt_number = 1`). A paid retry still records a personal best shown on ZDailyAfter («بهترین تلاشت»), but cannot buy a better prize rank. Touches `DailyRepository.GetDailyLeaderboard` / `GetUserRank`, `RunDailyPayout`, ZDailyAfter/Before copy, the admin daily detail.
- **Recompute the score on the server:** the client also uploads `word_times_ms[]` (one per word) on `POST /game/solo` for `mode: daily`; the server recomputes with the exact Flutter formula (needs `engine` to share the long-word rule — do S6's formula decision first or implement today's ×2 and change it in S6) and rejects a mismatch (`400 invalid_daily_chain`). Plausibility: each time 300 ms … 15 s (+8 s if Extra Time was used — upload a used-power-up flag per word or allow it). Uploads **without** timings (old apps) keep the bound check — the lenient one from S1 — until the minimum app version is raised.
- Timings are still client-reported; this closes the "post the max score" cheat, not a client that fakes its timings.

### S6 — Long-word bonus
**Status: not started.**

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
