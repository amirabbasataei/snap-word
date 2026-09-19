# REDESIGN_PLAN.md — زنجیر Visual Redesign

Screen-by-screen plan for implementing the Claude Design canvas in Flutter.

**Design source:** `https://claude.ai/design/p/4a90de7c-3340-476f-922d-213a9dcd6307` (`Zanjir.dc.html`)
**Access note:** WebFetch/browser access to `claude.ai/design/...` URLs returns 403 (needs claude.ai login not available to those tools). The reliable path is the `DesignSync` tool: `method: "get_file"` with `projectId: "4a90de7c-3340-476f-922d-213a9dcd6307"` and `path: "<File>.dc.html"` — this works even though `list_projects` doesn't surface this project (it's a canvas, not a design-system project). Per-screen files confirmed present via `list_files`: `ZHome`, `ZSolo`, `ZPlay`, `ZOver`, `ZLobby`, `ZVersus`, `ZDailyBefore`, `ZDailyAfter`, `ZBoard`, `ZProfile`, `ZFriends` (each `<Name>.dc.html`), plus `Zanjir.dc.html` (token sheet + screen imports) and `Vajechin Word Chain.dc.html`.
**Status:** Decisions made (see §1). Stage 1 (Foundation) in progress.
**Phase:** Phase 17 in the CLAUDE.md status table and PLAN.md (added — see PLAN.md Phase 17).

---

## 0. Summary

The design is **not a re-skin of the current UI — it is a different visual system.**

| | Current app | Design |
|---|---|---|
| Ground | Dark-only navy `#0B0E1C` | Warm paper `#F6F1E7` / warm-plum dark `#211D26` |
| Modes | Dark only (`themeMode` hardcoded) | Full light + dark, same markup, different token values |
| Language | English labels | Persian, RTL-native |
| Type | Material defaults | Vazirmatn 400–900 |
| Elevation | Blur shadows | **Zero blur** — solid offset edges only |
| Accent | One primary blue | Four co-equal accents (indigo/teal/amber/coral) |

Practically every widget's *visuals* get rewritten; nearly every widget's *state contract* survives. Blocs, cubits, repositories, and DI are untouched throughout.

**Design canvas contents:** 11 screens × 2 modes + a token sheet. Sections 2 (light) and 3 (dark) are the *same components* with different CSS variable values — that property is the single most important thing to preserve in the Flutter port.

---

## 1. Spec conflicts — settle before writing code

The design encodes game mechanics that contradict `CLAUDE.md`. Listed rather than silently resolved.

| # | Design shows | CLAUDE.md says | Where |
|---|---|---|---|
| 1 | **Lives** — «۲ جان», «سه جان داری؛ هر کلمهٔ نادرست یکی کم می‌کند» | First invalid word ends the match; one continue per player | ZSolo, ZVersus, ZDailyBefore |
| 2 | **Wager + turn-length picker** — 10/15/20s, بدون شرط / ۲۰ سکه / ۱۰۰ سکه | Turn timer fixed per variant (15s / 8s); no wagering in the coin economy | ZLobby |
| 3 | **Best-of-5 rounds** — «دست ۳ از ۵» | Single shared chain; first mistake loses | ZVersus |
| 4 | **Long-word bonus** — «۷ حرف · امتیاز دوبرابر» | base + speed + streak + rarity; no length multiplier | ZVersus |
| 5 | **Levels & badges** — «سطح ۱۲ · واژه‌باز», «نشان‌ها ۶ از ۲۴», accuracy %, unique-word count | No level, badge, accuracy, or unique-word fields in `player_stats` | ZProfile |
| 6 | **Referral codes** — «با کد دعوت، ۵۰ سکه بگیر · ZNJR-۴۸۲» | No referral system; not in the coin economy table | ZFriends, ZLobby |

Additional smaller drift:
- ZOver prices continue at **۵۰ coins**; spec says **25** (`GameConstants.continueCostCoins`).
- ZBoard has **4 tabs** (این هفته / امروز / همیشه / دوستان); spec has global-weekly + friends only.
- ZVersus shows a **typing indicator** («مریم دارد می‌نویسد») — no such event exists in the WebSocket protocol.
- ZDailyBefore states a **10s** turn timer; spec says Daily uses 15s.

### Recommendation

- **Adopt 1 and 4.** Lives is a better solo loop than instant death and is mostly `GameBloc` state; the long-word bonus is one line in the scorer. Both are cheap and self-contained.
- **Render 2, 3, 5, 6 as designed but wired to placeholders**, tracked as follow-up backend work. Each is a genuine backend feature (schema + Go service + API); half-building four subsystems mid-redesign would stall the visual work.

### Decisions (final)

1. **Lives** — Adopted as designed. Two lives, replacing instant-death-on-first-mistake, for both solo and multiplayer.
2. **Wager + turn-length picker (ZLobby)** — Build exactly as designed, no placeholder gating.
3. **Best-of-5 rounds (ZVersus)** — Build the visual UI as designed (round indicator, "دست ۳ از ۵"), wired to a placeholder. Round count is a **fixed constant (best of 5)**, not lobby-configurable — confirmed by the user; not a canvas-driven decision (canvas access wasn't needed for this one in the end). Real round-tracking logic (WS protocol + Go backend: round wins, round transitions, match-level winner) is separate follow-up backend work, not part of this visual redesign.
4. **Long-word bonus** — Adopted as designed.
5. **Levels & badges (ZProfile)** — Rendered as designed, wired to placeholders. Backend work (schema + fields) is follow-up.
6. **Referral codes** — Backend implemented (migration `003_phone_auth_referral`, `POST /auth/verify-otp` signup-time linking + `POST /referral/redeem` post-login). Client wired via `ReferralBottomSheet`, shared by ZLogin's teaser card (signup, +100 coins) and a new Profile → Settings entry (post-login, +50 coins, one-time). `ZLobby`'s `_InviteRow` room-code-invite placeholder is a different, unrelated feature and remains a stub.

**Drift fixed to match spec (not the canvas):**
- ZOver continue price: 25 coins (`GameConstants.continueCostCoins`), not the canvas's 50.
- ZDailyBefore turn timer: 15s (spec), not the canvas's 10s.
- ZBoard tabs and the ZVersus typing indicator: keep as noted in the follow-up list below — typing indicator needs a new WS event, not built now; turn banner ships without it.

**Phase bookkeeping:** Phase 17 — Visual redesign (زنجیر) added to the CLAUDE.md status table and PLAN.md, rather than editing the completed phases in place.

---

## 2. Stage 1 — Foundation

Everything else depends on this stage. Nothing below it can start until it lands.

### 2.1 Token system

`lib/core/theme/` is rewritten from a flat colour list into a token system:

```
core/theme/
  app_tokens.dart      ZColors extends ThemeExtension<ZColors>
                       ~28 named tokens × 2 value sets (light/dark) + lerp
  app_typography.dart  Vazirmatn TextTheme — the 8 roles from token sheet 4b
  app_spacing.dart     space 4·8·12·14·18·22·26 (screen gutter 18);
                       radii tile 8–12 / chip 999 / card 16–20 / sheet 24–28;
                       tile sizes 26 · 34 · 42–56 · 96; hit target ≥ 44
  app_elevation.dart   solidEdge(deep, y) → [BoxShadow(blurRadius: 0, offset)]
  app_motion.dart      180ms easeOutBack · 140ms easeOut · shake 90ms×2 ·
                       timer 1s linear · theme cross-fade 200ms
  app_theme.dart       light/dark ThemeData wiring the extension
```

**The core discipline: a screen never names a hex value.** Screens read `context.z.indigo`, `context.z.onIndigo`. Light/dark then costs nothing per screen — which is exactly how the design file works. Any hardcoded colour in a screen file is a bug.

Token list (from design sheet 4a) with confirmed hex values, pulled via `DesignSync get_file` on `Zanjir.dc.html` (CSS custom properties on sections `#t2` light / `#t3` dark match the 4a table):

| token | light | dark |
|---|---|---|
| paper | `#F6F1E7` | `#211D26` |
| surface | `#FFFFFF` | `#2B2632` |
| line | `#E3DCCC` | `#3B3543` |
| wash | `#F0EBE0` | `#38313F` |
| ink | `#1E1B2E` | `#F2EDE3` |
| ink60 | `#6B6780` | `#B9B2C2` |
| ink40 | `#8B8798` | `#8E8799` |
| indigo / indigoDeep | `#4C5FE0` / `#3546B8` | `#7180EE` / `#414FB6` |
| teal / tealDeep | `#16A38F` / `#0E8071` | `#2CBBA4` / `#178A79` |
| amber / amberDeep | `#F5A524` / `#C97F0C` | `#F7B44A` / `#C1832A` |
| coral / coralDeep | `#EF4B3C` / `#C22E22` | `#F4685A` / `#BE4034` |
| onIndigo / onIndigoSoft | `#FFFFFF` / `#C9D0FA` | `#14122B` / `#221F4A` |
| onTeal / onTealSoft | `#FFFFFF` / `#BFEDE5` | `#0C2A25` / `#0F3B33` |
| onAmber | `#3A2606` | `#2A1A04` |
| onCoral | `#FFFFFF` | `#2C0E09` |
| inkSurface / inkSurfaceDeep | `#1E1B2E` / `#0C0A16` | `#F2EDE3` / `#C8C0B2` |
| onInkSurface / onInkSurfaceSoft | `#FFFFFF` / `#9F9BB0` | `#211D26` / `#6A6273` |
| tintIndigo | `#E7EAFD` | `#2A2E52` |
| tintTeal | `#E1F4F0` | `#123A34` |
| tintCoral | `#FDEAE7` | `#452724` |

Notes from the token sheet: tile hues keep identity in dark mode (lightened ~12%, paired with dark ink labels where contrast demands it). Dark ground is warm plum `#211D26` (hue ≈ 300, not 0-chroma black) — all four accents stay in play, no single glowing signal color. The player's own chain bubble inverts to cream in dark mode so the "ink on paper" metaphor survives at night.

**Typography roles** (Vazirmatn, letter-spacing 0 everywhere except the wordmark at −0.5px; Persian digits ۰۱۲… everywhere, thousands separator «٬»):

| role | size / weight | line height |
|---|---|---|
| display (score, seed letter) | 40–60 / 900 | 1.0 |
| screen title | 19–21 / 900 | 1.25 |
| chain word — active | 21 / 900 | 1.0 |
| chain word — history | 16–19 / 800 | 1.0 |
| card title | 13.5–15 / 800 | 1.3 |
| body | 12.5 / 500–600 | 1.6 |
| meta / label | 11–11.5 / 600 | 1.4 |
| button | 15–17 / 900 | 1.0 |

**Elevation:** zero blur shadows anywhere. Solid offset edge in the accent's deep variant — cards `0 3px 0 line`, tiles & primary buttons `0 4px 0 accent-deep`. Pressed state removes the offset and translates Y +3.

**Motion:** tile drop / word commit 180ms `easeOutBack`; bubble enter (chain) 140ms fade + 8px slide `easeOut`; timer bar linear 1s ticks, turns coral under 5s; wrong word shake 90ms×2 at 6px amplitude; theme switch 200ms color cross-fade with no layout change; Rive/Lottie reserved for streak flame, game-over burst, match-found handshake only.

### 2.2 Other Stage 1 work

- **Vazirmatn font** — not currently in `pubspec.yaml`. Vendor the .ttf files (400/500/600/700/800/900) to `assets/fonts/` and declare them.
- **Persian digits** — `core/utils/persian_digits.dart`. Every number in every screen renders as ۰۱۲۳ with «٬» thousands separator. One formatter, used everywhere.
- **Theme mode** — `main.dart:65` hardcodes `themeMode: ThemeMode.dark` and no light theme exists. Add a `ThemeCubit` + `shared_preferences` persistence, driven by the حالت شب toggle in ZProfile.
- **RTL audit** — `main.dart:71` wraps the tree in `Directionality.rtl` with a comment admitting the tree was never audited. Now it matters: `EdgeInsets.only(left:)` → `EdgeInsetsDirectional`, `Row` alignment → `start`/`end`.
- **Bottom nav** — the design draws a custom bar (square glyphs, Persian labels خانه / جدول / دوستان / من). Replaces the Material `BottomNavigationBar` in `_MainShell` (`core/router/app_router.dart:130`).

### 2.3 Shared widgets — `lib/core/widgets/`

Extracted because they repeat across three or more screens:

| Widget | Appears in |
|---|---|
| `LetterTile` (size, accent, rotation, solid edge) | **all 11** — the atom of the whole system |
| `SolidCard` (surface + 1px line + `0 3px 0 line`) | all 11 |
| `AccentButton` / `NeutralButton` (press → remove offset, translateY +3) | 8 |
| `CoinPill` (۱٬۲۴۰ + amber dot) | 4 |
| `TintChip` | 6 |
| `AvatarTile` (32–64px rounded-square initial) | 5 |
| `SectionHeader` | 4 |
| `StreakStrip` (7–8 day chips) | ZHome, ZDailyBefore, ZDailyAfter |

### 2.4 Stage 1 — done

Landed: `core/theme/{app_tokens,app_typography,app_spacing,app_elevation,app_motion,app_theme,theme_cubit}.dart`, vendored Vazirmatn (400/500/600/700/800/900, `assets/fonts/`, declared in `pubspec.yaml`), `core/utils/persian_digits.dart`, all eight shared widgets in `core/widgets/`, and `ZBottomNav` wired into `_MainShell` (`core/router/app_router.dart`) with Persian labels (خانه/جدول/دوستان/من) — Material icons stand in for the canvas's bespoke square glyphs, which aren't available as assets.

`AppColors`/`AppTheme.dark` (the legacy flat palette) are kept byte-identical and still drive all 11 unmigrated screens directly — they don't read `Theme.of(context)`, so a straight removal would have broken every screen before its redesign stage. `AppTheme.dark` now also carries `fontFamily: 'Vazirmatn'` and the `ZColors.dark` extension, so the global font swap applies immediately everywhere and new `context.z`-based widgets (bottom nav, shared widgets) resolve correctly. `ThemeCubit` defaults to `ThemeMode.dark` and isn't yet exposed as a UI toggle (that lands with ZProfile in Stage 5) — switching to light now would look broken, since unmigrated screens ignore the active theme entirely.

**Verification:** `flutter analyze` — no issues. `flutter test` — all existing tests pass unchanged. Could not visually verify on a running app in this sandbox: web fails (Drift/sqlite3 has no WASM setup for this project's web target — pre-existing, unrelated to this change), iOS simulator fails during Xcode's Swift Package Manager resolution (Firebase binary CDN 404s — pre-existing, unrelated), and the Android emulator fails to boot in this sandbox. Visually confirm the new bottom nav and font on a real device/CI before starting Stage 2.

---

## 3. Stage 2 — Core loop

| Screen | Reuses | New |
|---|---|---|
| **ZHome** ← `features/home/view/home_screen.dart` (545 ln) | `_StreakBadge`, `_DailyChallengeButton`, `_ResumeCard`, `_GuestBanner`, `_QuickPlayCard` logic + nav wiring | Wordmark (5 rotated letter tiles), streak strip, indigo daily hero, 2×2 mode grid, weekly-rank teaser row |
| **ZSolo** ← `features/game/view/game_screen.dart` `_SoloHeader` + `_ActiveGameScreen` | `GameBloc` contract unchanged; `word_input.dart` logic | **New chain renderer** — vertical spine rail (2px line), tiles stepping 26→34px and opacity .4→1 down the list, stat strip (طول زنجیر / رکورد / جان) |
| **ZPlay** ← same screen, AI mode | Same bloc; `_PowerupRow` / `_PowerupButton` logic | **Second chain renderer** — chat-style alternating bubbles: opponent = `surface` + border on the start side, you = inverted `inkSurface` on the end side |
| **ZOver** ← `_GameOverScreen` (`game_screen.dart:781`) | `GameOver` state, share + continue actions | Full-bleed `inkSurface` hero band with 28px bottom radius, tumbling letter tiles, score card, chain-tail chips |

**Structural note:** today one `WordChainList` serves both solo and AI. The design wants **two distinct renderers**. Keep `WordChainList` as the shared scroll / auto-scroll shell and give it two presentation strategies rather than duplicating the controller logic (`features/game/view/widgets/word_chain_list.dart`).

### 3.1 Stage 2 — ZHome, ZSolo, ZPlay, ZOver all landed

Landed: `home_screen.dart` rewritten against `context.z` tokens — wordmark (5 rotated `LetterTile`s, rectangular 38×48 variant), streak card (`StreakStrip` rewritten to render real trailing-7-day weekday letters computed from `StatsDao`'s `dailyStreak`/`lastPlayedDate`, replacing the earlier checkmark-based guess now that the canvas was confirmed), indigo daily-challenge hero (real seed letter + backend `todaysBest` + a locally-computed hours-to-next-midnight-UTC countdown, best-effort network fetch with graceful fallback), 2×2 mode grid (تک‌نفره / حریف هوشمند / رویارویی آنلاین, same nav destinations as the old `_QuickPlayCard`s), and a weekly-rank teaser row (real `playerRank` from `LeaderboardRepository`). `_ResumeCard` and `_GuestBanner` kept their exact trigger conditions, restyled onto `SolidCard`. The mode-select and difficulty bottom sheets were also restyled onto tokens (not in the canvas, but shown directly from ZHome — leaving them on the legacy dark-only `AppColors` would break under light mode).

Widget API additions made to support this (all backward compatible — neither widget had any other call site yet): `LetterTile` gained optional `height`/`radius`/`fontSize` overrides for the wordmark's non-square tiles; `SolidCard` gained `elevated` (the streak card has no offset shadow in the confirmed design, unlike every other card).

The two top-right icon buttons in the canvas (settings-like square, notification-like circle) have no defined behavior in the mock. The first is temporarily wired to `ThemeCubit.toggle()` so light/dark can actually be checked on-device before ZProfile ships the real حالت شب switch in Stage 5 — flagged here so it isn't mistaken for a deliberate final placement; replace when ZProfile lands.

**Verification:** `dart analyze` and `flutter test` clean. Actually launched on an iOS 26 simulator (`flutter run`) — first launch hit a real bug (`Row(crossAxisAlignment: stretch)` inside the unbounded-height scroll column threw `BoxConstraints forces an infinite height` and silently blanked the entire body below the top bar; fixed by wrapping in `IntrinsicHeight`). Confirmed via on-device screenshots, both themes, including a temporary data-injection pass (reverted before commit) to exercise the streak card and daily hero, which a fresh guest session doesn't otherwise populate.

**Entry-flow fix (predates the ZSolo rebuild):** `home_screen.dart`'s تک‌نفره card used to open a bottom sheet asking Classic vs. زمان‌دار before every solo game. Tapping تک‌نفره now goes straight into Classic (`_startSolo` pushes `/game` directly, no sheet); زمان‌دار moved to a small indigo-colored tappable segment inline in ZSolo's own header subtitle ("⏱ حالت زمان‌دار" / "🎯 حالت کلاسیک" to switch back), which restarts the match in the other mode immediately if no words have been played yet, or behind a confirm dialog if the chain is non-empty. `_showModeSheet` is unchanged and still used for the AI-difficulty flow (`_startVsAi`), which wasn't in scope for this fix.

**ZSolo** ← new `features/game/view/z_solo_screen.dart`. Vertical spine chain renderer: each row is a `LetterTile` (accent cycling indigo→teal→amber→coral by index) + word + `"index · +score"` meta, opacity/size ramped by distance from the most recent word (`_rampSizes`/`_rampFonts`/`_rampOpacity`, floor at the oldest step for long chains) with the spine line rendered as small per-gap segments (not one absolutely-positioned line — the canvas's continuous line is always occluded by the tiles anyway, so per-gap segments reproduce it exactly without fighting `ListView`'s scroll extent). The most recent word gets the raised/embossed tile + a `"+score · تازه"` tint chip. Stat strip: طول زنجیر (`wordChain.length`), رکورد تو (`StatsDao.bestMatchStreak`, fetched once in `initState`), and either lives pips (classic) or remaining match time (time_attack, third tile swaps since lives don't deplete outside classic — see Lives below).

**ZPlay** ← new `features/game/view/z_play_screen.dart`. Chat-bubble renderer: opponent bubbles (`surface` + border, aligned to the RTL start/right side) always show the difficulty label; "you" bubbles (`inkSurface` fill, aligned end/left) only show a "تو · +score" label on the most recent one, matching the canvas exactly. A real bug caught before it shipped: `wordScores` only ever accumulates the player's *own* words (see `GameBloc._onWordSubmitted`), so it isn't parallel to `wordChain` once the AI's interspersed words are counted — a bubble's score has to be looked up by a separate "my move" counter, not by chain index (`z_play_screen.dart`'s `_BubbleChain.build` tracks `myMoveIndex` for this). Footer has 4 power-up slots (hint/freeze/extra-time/shield) vs. ZSolo's 3 — freeze only applies with an opponent.

**ZOver** ← new `features/game/view/z_over_screen.dart`. Merges what used to be two separate screens (the `ContinuePrompt` overlay and `_GameOverScreen`) into the canvas's single design: `inkSurface` hero band (inverts to cream in dark mode, by design — see the token sheet's note on `inkSurface`) with 3 decorative tumbling tiles, a score card, a near-miss bar ("N کلمهٔ دیگر تا شکستن رکوردت مانده بود") or a new-record banner (mutually exclusive, both driven by `StatsDao.bestMatchStreak` vs. `chainLength`), chain-tail chips, then either the continue actions (ad/coins/share, only while `canContinue && !isSaved && continueTimeRemaining > 0`) or just share+home. Reused for both solo and vs-AI game-overs; **routes only when `state.opponentType != null`** — true multiplayer's WS-driven `GameOver` never sets that field (see `_handleWsLossEvent`/`_handleWsGameOver` in `game_bloc.dart`), so it's the correct discriminator (the existing `GameOver.isMultiplayer` getter was the wrong one to reuse here — despite its name it's also `true` for vs-AI once `opponentScore > 0`). Multiplayer keeps the legacy `ContinuePrompt`/`_GameOverScreen` pair untouched (Stage 4). Daily-mode `GameOver`s are intercepted first and just show the existing saving-spinner, since ZDailyAfter (Stage 3) owns the real result screen. Continue price fixed at `GameConstants.continueCostCoins` (25), not the canvas's 50, per the decision already recorded above. `ShareService` gained a small `shareMatch({score, chainLength})` (the canvas's "هم‌رسانی نتیجه" button) alongside the existing daily-only `shareDaily`.

**Lives (adopted per decision 1, scoped down from the plan):** implemented in `GameBloc` for **solo + classic mode only** (`GameConstants.soloLives = 2`) — not vs-AI (ZPlay's canvas has no lives strip at all, unlike ZSolo/ZVersus/ZDailyBefore) and not time_attack (existing early-finalize-on-any-mistake behavior for time_attack was left untouched rather than silently extended by the lives change — flagged as a pre-existing spec/code mismatch below, not fixed here). A mistake in solo/classic with lives remaining decrements `GameActive.livesRemaining` and keeps the match going (`GameState.lastMistakeReason` surfaces a transient "you lost a life" banner); the match only actually ends via the existing `_handleGameOver` path once lives hit 0. True multiplayer/AI lives (decision 1's full scope) are deferred to Stage 4.

**Long-word bonus (decision 4):** added to `GameBloc._calculateScore` only (words ≥ `GameConstants.longWordBonusMinLength` (7) double their score) — Flutter-side only, since solo/AI never touch the Go backend's scorer (per CLAUDE.md, solo/AI run entirely on-device). The Go backend scorer is unchanged; that's a separate, not-yet-scoped follow-up for when multiplayer picks up this bonus too.

**Small pre-existing gap fixed in passing:** `StatsDao.recordGameResult` never actually updated `bestMatchStreak` (it just carried the existing value forward unchanged) — meaning "your record" had no real data source. Added a `chainLength` parameter, now `max(existing, chainLength)`; `GameBloc._saveAndEmitFinal` passes `over.chainLength`.

**Flagged, not fixed (out of this stage's scope):**
- `GameBloc._onWordSubmitted`'s validation regex (`^[a-z]+$`) only accepts Latin lowercase letters, meaning as written it would reject every real Persian word before ever reaching `DictionaryService.isValid` — yet `DictionaryService` itself (and its test suite) is fully Persian/ZWNJ-aware. This looks like a leftover from an earlier English prototype of the bloc that was never updated when the dictionary went Persian; it's a Phase 5 (engine)/Phase 2 (game feature) concern, not a Phase 17 visual one, so it was left untouched and is called out here rather than silently patched.
- Time Attack currently ends the match on the player's very first mistake (`_onWordSubmitted`/`_onTimerTicked` call `_handleGameOver`/`_finalizeGame` unconditionally outside the classic-lives branch), which doesn't match CLAUDE.md's "Time Attack ends only when the 90s total runs out" — pre-existing, not introduced or fixed here.
- ZPlay's ادامه‌"انجماد حریف" (freeze) power-up, like Extra Time and Shield, is rendered per the canvas but left as a disabled/inert placeholder (`enabled: false`), matching the current app's existing behavior for those three — the power-up inventory/spend system is Phase 16 territory and wasn't touched.

**Verification:** `flutter analyze` and `flutter test` clean throughout. Actually launched on the same iOS 26 simulator used for ZHome (`flutter run`), both themes, all three screens, via a temporary preview-harness route (`/_preview/:screen?theme=`) that rendered each screen directly off a hand-built `GameActive`/`GameOver` fixture through the real DI container — reverted before commit, `git diff` on `app_router.dart` confirmed clean. Caught and fixed two real bugs this way: the hint power-up's "؟" glyph had no indigo badge behind it (invisible white-on-cream) — now `ZHintIcon`; and `ZWordInput`'s `TextField` was silently inheriting the legacy dark theme's navy `filled` decoration through the ambient `InputDecorationTheme` — fixed with an explicit `filled: false`. A few things that looked like bugs at a glance turned out not to be on closer inspection (worth recording so they aren't re-litigated): the "‎+score · index" meta text's bidi ordering renders correctly once actually zoomed in; Vazirmatn's isolated-form "ه" glyph looks like a teardrop/almost-"۵" shape at small sizes but is byte-verified correct in every case checked.

---

## 4. Stage 3 — Daily Challenge — complete

`ZDailyBefore` / `ZDailyAfter` ← `features/daily/view/daily_screen.dart`, fully rewritten on tokens. `DailyCubit`/`DailyRepository` untouched, per plan.

**ZDailyBefore**: back header (weekday + numeric date, see below), indigo seed-letter hero (96×106, `ZTileSize.dailySeed`, built as a raw `Container` like `ZHome`'s `_DailyHero` rather than through `LetterTile` — the canvas's surface-bg/indigo-text combo doesn't match any of `LetterTile`'s accent variants), three-row rules card, streak card (reuses the shared `StreakStrip` widget rather than redrawing the canvas's plain bars, for one visual system app-wide), ink-filled primary CTA, "دیدن جدول امروز" secondary button routed to `/leaderboard` (flagged below — no per-day leaderboard view exists yet).

**ZDailyAfter**: teal result hero (chain length + rank + score — no fabricated percentile/total-player-count, see below), chain chips with longest-word highlight and «+N دیگر» overflow, streak card with "+۱ امروز" badge, live-ticking countdown to next-midnight-UTC (`Timer.periodic`, disposed), share button, "جدول امروز"/"بازی تک‌نفره" row, and the **retry button + comparison card preserved** — the canvas has no retry UI at all, but it's real spec'd functionality (`POST /daily/retry`, 25 coins) that a visual redesign shouldn't silently drop, so it's kept and restyled rather than removed.

**Real-data-only policy**: the canvas shows several stats the API doesn't provide — ZDailyBefore's "۸٬۲۳۰ نفر امروز بازی کردند · میانگین ۱۲ کلمه" (global player count / average words) and ZDailyAfter's "بهتر از ۷۸٪ بازیکن‌ها" (percentile). `DailyChallenge` has no such fields. Rather than fabricate numbers, these were replaced with real fields already available: `todaysBest` for the before-hero's subtitle, and `rank`/`score` (no percentile) for the after-hero. Flagging in case a backend field for this is wanted later.

**Calendar date**: the canvas shows a full Jalali calendar date ("شنبه ۱۶ شهریور ۱۴۰۵"). At the time this stage was written, the app had no Jalali calendar conversion anywhere, so the Persian weekday name plus the real Gregorian day/month in Persian digits was substituted instead ("پنجشنبه ۱۰/۰۹"). **Update**: a later commit (`9e6db14`, pre-Stage-4) added the `shamsi_date` package app-wide, and `daily_screen.dart`'s header now does a real `Jalali.fromDateTime()` conversion, matching the canvas's full Jalali date (e.g. "پنجشنبه ۱۶ شهریور"). The Gregorian-substitute described above is superseded.

**Lives extended to Daily** (per user decision, matching the original conflict-table scope of ZSolo/ZVersus/ZDailyBefore): `GameBloc._onWordSubmitted`'s and the timeout handler's lives-gate now also cover `mode == 'daily'` (previously `classic`-only), so a Daily attempt costs a life on a mistake instead of ending instantly, using the same `GameConstants.soloLives` (2, not the canvas's literal "سه جان"/3 — kept consistent with the already-adopted 2-life decision). Daily's separate `dailyMaxWords` (20-word) cap is untouched. `ZSoloActiveScreen`'s header (already the actual Daily gameplay screen, since `game_screen.dart` routes any `opponentType == 'solo'` match there regardless of mode) now shows "چالش روزانه" instead of "تک‌نفره" and hides the زمان‌دار mode-switch toggle for `mode == 'daily'` — that toggle would have silently abandoned the tracked daily attempt and restarted as a fresh time_attack solo match, a real bug that predates this stage but was only surfaced by building Daily out properly.

**Bugs fixed before starting this stage** (reported and user-approved, not part of the visual work):
1. `_startVsAi`'s difficulty sheet was chaining into the legacy classic/زمان‌دار mode sheet right after (`home_screen.dart`, same leftover-sheet pattern as the earlier `_startSolo` fix). Now goes straight to a classic vs-AI match; `_showModeSheet` (now unused) removed. Side effect: there's currently no UI path to start Time Attack vs AI (ZPlay has no inline mode toggle, unlike ZSolo) — flagged, not silently fixed.
2. `GameBloc._onWordSubmitted`'s character-validation regex (`^[a-z]+$`, Latin-only) was rejecting every real Persian word in solo/AI play before it ever reached `DictionaryService.isValid` — a total block on core gameplay. Same bug also existed in `tutorial_screen.dart`. Both fixed to use a new `DictionaryService.hasValidChars()` (extracted from `isValid`'s own correct Persian-character check) instead of duplicating the character-class regex by hand.

**Verification**: `flutter analyze` and `flutter test` clean throughout. Verified interactively on the iOS 26 simulator via a temporary preview harness (`DailyPreviewScreen` in `daily_screen.dart` + a `/_preview/daily/:variant?theme=` route in `app_router.dart`, `initialLocation` pointed at it for a cold-start screenshot instead of live taps — this session had no working tap/type automation into the simulator, see below) — both screens, both themes, via `xcrun simctl io ... screenshot`. Caught and fixed one real bug this way: the chain-chip highlight was computed as the longest word across the *entire* chain, which frequently fell inside the "+N دیگر" overflow and never appeared — fixed to compute over the visible chips only. Harness fully reverted before commit (`git diff` on `app_router.dart` empty).

**Simulator interaction gap**: this session could not drive touch/keyboard input into the iOS simulator (no `cliclick`/`idb` installed, and AppleScript/System Events lacked accessibility permission) — screenshots and the preview-harness technique substituted for live tap-through verification. Worth fixing the environment (grant accessibility access, or install `cliclick`) before the next session that needs on-device interaction testing, e.g. the actual word-submission flow.

---

## 5. Stage 4 — Multiplayer — complete, verified on-device 2026-09-17

`ZLobby` fully rewritten on tokens (`features/lobby/view/lobby_screen.dart`); `LobbyCubit`/`LobbyState`/`LobbyRepository` untouched. `ZVersus` is a new screen (`features/game/view/z_versus_screen.dart`), replacing the legacy `_ActiveGameScreen`/`_MultiplayerHeader`/`_TurnIndicator`/`_NextLetterBar`/`_PowerupRow` block in `game_screen.dart` (now deleted — confirmed unreferenced elsewhere before removing) the same way ZSolo/ZPlay replaced their legacy counterparts in Stage 2. `game_screen.dart` now wraps `ZVersusActiveScreen` in the pre-existing `_OpponentContinueOverlay`/`_DisconnectedBanner` Stack rather than the screen owning it, so those two overlays (and the legacy English `ContinuePrompt`/`_GameOverScreen` pair for multiplayer game-over, per Stage 2's note) stay untouched and out of this stage's declared scope — REDESIGN_PLAN.md's own Stage 4 bullet list only ever named the active-game header/turn-banner/locked-input, not game-over or the overlays.

**ZVersus**: dual score header (real avatars via first-letter `LetterTile`, real `opponentUsername`/scores), a colored turn-banner pill (teal/`tintTeal` on my turn, coral/`tintCoral` on the opponent's, matching the canvas's coral-only frame) with an inline countdown bar, and the same chat-bubble shared-chain renderer as ZPlay (opponent bubbles bordered/left, mine on `inkSurface`/right) but keyed off the real `myPlayerId`/`opponentUsername` instead of AI-difficulty labels. Footer reuses `ZWordInput`'s existing `isOpponentThinking` lock (`enabled: state.isMyTurn`) — same component, no protocol change, so the copy reads "‌[نام] در حال فکر کردن…" rather than the canvas's generic "منتظر نوبت…"; close enough in meaning not to fork the shared widget for one string. Added a small back button (not in the canvas at all) since a live match has to stay leaveable — same category of "flag a real functional need beyond the canvas" as the VS-AI mode-toggle fix earlier this stage, not a style choice.

**Decision-table items resolved for this stage** (see §1):
- **Decision 1 (lives)** — **not extended to multiplayer, despite being in the "adopt" bucket.** `GameBloc`'s multiplayer path is 100% server-authoritative (`_onWordSubmitted` just forwards `submit_word` over WS; `word_rejected` is immediately followed by `loss_event`, confirmed by reading the handler — no grace period exists server-side). A lives chip here would either be decorative-and-misleading (shows "۲ جان", match still ends on the first mistake) or require real Go backend changes, which are out of this Flutter-only redesign phase. Omitted the canvas's "۲ جان" footer chip entirely rather than fake it — flagging for a real decision once/if the Go WS protocol grows a lives concept. `GameConstants.soloLives`/`GameActive.livesRemaining` untouched (still solo/daily-only, exactly as before).
- **Decision 2 (wager + turn-length picker)** — built as an interactive picker (real tap/selection state, restyled `_Chip`s) per "no placeholder gating," but **not wired to the match/queue call** — `POST /match/queue` has no field for a custom turn duration or a coin wager (CLAUDE.md's timers are fixed per variant; there's no wager system in the coin economy). Cosmetic by necessity, flagged in a code comment and here.
- **Decision 3 (best-of-5 rounds)** — rendered as a static "دست ۱ از ۵" (new `GameConstants.multiplayerRoundsTotal = 5`), never incremented — no round-tracking WS event exists. Placeholder per the decision, not silently dropped.
- **Referral/invite (decision 6, ZLobby)** — room-code invite card rendered as designed; "دعوت" is a snackbar placeholder (no join-by-code backend).
- **Typing indicator** — per the decision table, deliberately **not built** (needs a new WS event; turn banner ships without it, exactly as decided).

**Real-data-only policy, again**: the canvas's "حریف‌های اخیر" list (fabricated per-opponent win/loss records) and "۳٬۴۰۱ آنلاین" badge on the Find-Match button have no backing endpoint. Dropped the online-count badge outright; replaced the recent-opponents list with a "دوستان" card backed by the real `FriendsRepository.fetchFriends()` (real username + real weekly score, no fabricated record), and wired its "دعوت" button to the **real** `POST /challenges` call (`FriendsRepository.sendChallenge`) instead of a fake room-code join — arguably more useful than the canvas's non-functional version, since Friends/Challenges (Phases 11/12/14) are already fully built. A small "نوع بازی" (classic/زمان‌دار) toggle was added above the decorative pickers — not in the canvas at all — because the canvas drops the classic/time-attack choice entirely in favor of the turn-length picker, and silently losing the ability to queue for multiplayer Time Attack would repeat the exact regression class just fixed for VS-AI earlier this stage.

**Follow-up backend work (confirmed out of scope, not faked client-side)** — re-audited 2026-09-17: `backend/` has zero wager or round-tracking concept anywhere (checked the WS protocol, `internal/service`, and migrations). Building either further requires real Go work, not more Flutter:
1. **Wager** — a `wager` field on `POST /match/queue`, a coin-hold/deduct/refund flow in the matchmaking service, and a payout rule on match end. No entry in the coin economy table today.
2. **Best-of-5 rounds** — new WS events (`round_won`/`round_transition` or similar), server-side round state in the match/game service, and a match-level (not chain-level) winner rule. Today the server only knows a single shared chain that ends on the first mistake.

Per the no-fake-mechanics rule already applied to multiplayer lives (decision 1 above), neither was built as client-only fake state — both stay the cosmetic pickers/placeholder described above until this backend work happens.

**Verification (2026-09-17)**: `flutter analyze` clean throughout. Verified interactively on-device (iOS 26 simulator, real backend + Postgres + Redis running locally, real WS multiplayer match against the AI-fallback opponent — dark theme; light theme not independently re-tapped this pass, but both screens are 100% `context.z` token-driven with zero hardcoded colors, the same pattern already confirmed in both themes for Stages 1–3, so risk is low). This pass caught and fixed real, previously-hidden bugs that static analysis and the earlier code-only pass had missed — multiplayer was **completely non-functional end-to-end** before these fixes:
1. **`POST /match/queue` client timeout** (`lobby_repository.dart`) — the endpoint deliberately long-polls up to `AIFallbackWaitSec+5` (35s) server-side, but the app-wide Dio client's `receiveTimeout` was 10s, so every non-instant match failed client-side before the server could ever respond. Fixed with a per-request 40s timeout override, scoped to this one call.
2. **Match-found signal never reached the client** (`lobby_cubit.dart`) — `joinQueue`'s 200 response already contains the resolved `room_id`/`is_ai` (the long-poll's whole point), but the repository discarded the body and `LobbyCubit` waited only on an FCM push notification to learn the match had started — a channel not configured for local/simulator use. Fixed by parsing the response into a `MatchQueueResult` and emitting `LobbyMatchFound` directly from it (the push listener stays as a documented backup for the app-backgrounded case).
3. **`/api/v1/ws/game/:roomID` mounted behind header-only `RequireAuth`** (`backend/cmd/server/main.go`) — `ServeWS` was written to self-authenticate via the `?token=` query param (its own doc comment says so — a WS handshake can't carry an `Authorization` header), but it was routed inside the `protected` group, so the header-checking middleware rejected every real WS connection attempt with 401 before `ServeWS` ever ran. Moved the route out of `protected`.
4. **`_handleWsGameStart` crashed on every `game_start` event** (`game_bloc.dart`) — cast `gameState['players']` (a plain `List<String>` of user IDs per `gameStartState` in `room.go`) as `List<Map<String, dynamic>>`, throwing `type 'String' is not a subtype of type 'Map<String, dynamic>'` and leaving `GameBloc` stuck in `GameLoading` (a blank screen) forever. Also read a `current_player` key that doesn't exist — the real field is `current_turn` — so `isMyTurn` always fell back to `true`. Fixed to match the real wire shape; `opponentUsername` is left `null` (the server sends no username over WS at all — `ZVersusActiveScreen` already has a generic "حریف" fallback for this).
5. **Next-letter hint corrupted for every word** (`backend/internal/ws/room.go`, both `processSubmitWord` and `sendCurrentState`) — computed as `word[len(word)-1]`, the last *byte* of a UTF-8 string, not the last rune; every Persian word is multi-byte per letter, so this always produced a garbage/mojibake character (rendered as "§" in the client) instead of the real required starting letter. Fixed by exporting `engine.lastLetter` as `engine.LastLetter` (already correct — ZWNJ-stripped, rune-safe) and calling it from both sites, guaranteeing the hint always matches what `engine.ValidateMove` will actually accept.

All five are real client/backend contract bugs caught only by an actual live match, exactly the class of bug this project's testing convention (CLAUDE.md/session notes) already flags on-device verification for. None are new backend feature work — all are fixes to code from already-"Complete" phases (7–9) that never worked as designed. `go build`/`go vet`/`flutter analyze` clean after all fixes; `go test ./internal/engine/... ./internal/ws/...` still has pre-existing failures unrelated to this session's changes (confirmed via `git stash` — see below), not introduced by any of the above.

**Flagged, not fixed (out of this session's scope)**:
- `ws: UpdatePlayerScore failed ... invalid input syntax for type uuid` — the AI opponent's synthetic user ID (`"ai:" + difficulty + ":" + roomID[:8]`, not a real UUID) gets written to a UUID column when persisting final scores on match end/disconnect. Pre-existing (Phase 9), reproduces on every AI match's game-end path; a real bug but a persistence/stats-schema fix, not a Stage 4 visual-redesign item.
- `go test ./internal/ws/...` has 3 pre-existing failures (`TestRoomWordAccepted`, `TestRoomWordRejectedWrongLetter`, `TestRoomAlternatingTurns`) and `go test ./internal/engine/...` has 4 (`TestSelectAIWord_*`, all "expected a word, got empty string") — confirmed via `git stash` to already fail identically before any change made this session. Both contradict CLAUDE.md's ≥70%-coverage/passing-tests convention for "Complete" phases; worth a dedicated follow-up session, not investigated further here.
- Wager (§1 decision 2) and best-of-5 round tracking (§1 decision 3) remain the documented cosmetic placeholders — confirmed again this session that neither has any backend support to wire to (no wager field/coin-economy entry anywhere in `backend/`, no round concept in the WS protocol or Go service layer). Per the same no-fake-mechanics rule already applied to multiplayer lives, neither was built as client-only fake state.

### Stage 4 (continued) — ZLogin (ZPhone), ZOtpVerify (ZOtp)

- Screens: 3l (Login), 3m (OTP Verify) — canvas files `ZPhone.dc.html`/`ZOtp.dc.html`. Superseded the email/password `ZLogin`/`ZRegister` pair this section originally described: the design moved to phone number + 4-digit OTP (no password at all), so email/password auth was **fully removed**, not incrementally wired — `backend/internal/service/auth.go`, `repository/user.go`, `handler/auth.go` all rewritten; migration `003_phone_auth_referral` drops `email`/`password_hash` and adds `phone`, `otp_*`, `referral_code`, `referred_by`, `phone_verified_at`.
- Implementation checklist:
  - [x] `ZLoginScreen` (`features/auth/view/z_login_screen.dart`) — phone input (grouped Persian digits, LTR), carrier auto-detect line, terms checkbox gating submit, `POST /auth/send-otp`, referral teaser card
  - [x] `ZOtpVerifyScreen` (`features/auth/view/z_otp_verify_screen.dart`) — 4-box OTP row (auto-advance via a custom keypad, not the system keyboard — matches the canvas's own hand-drawn keypad), "ویرایش" pops back to ZLogin preserving the entered phone (route push, not go), server-driven resend countdown + voice-call fallback, `POST /auth/verify-otp` incl. optional referral code
  - [x] Error states mapped to Persian messages client-side from the server's machine-readable codes (`invalid_code`, `code_expired`, `too_many_attempts`, etc.) — see `_mapOtpError`/`_mapSendError` in the two screens
  - [x] Loading/submit state on both screens
  - [x] Success flow: both new- and existing-user verify-otp success → `context.go(returnPath ?? '/home')`
  - [x] Real on-device/simulator interactive verification (taps, keypad, countdown, RTL + Persian-digit rendering, both referral entry points) — done by AmirAbbas on-device using the `1111` dev/test OTP bypass code (no Kavenegar account purchased yet); both referral entry points exercised, no bugs found. Real SMS delivery via Kavenegar is still unverified end-to-end pending account purchase — the OTP flow itself is confirmed working via the bypass code, not via an actual sent SMS.

**Referral system** (decision 6, §1): built alongside this screen pair since the referral teaser card lives on ZLogin itself. See the updated §1 decision-table row and `CLAUDE.md`'s new "Referral Code System" section for the full design (two entry points sharing one `ReferralBottomSheet` widget, +100/+50 coins, no referrer-side reward yet).

**Verification note**: backend (`go build`, `go vet`, `go test`) is clean, including new nil-DB unit tests for the OTP/referral paths. `flutter analyze` and `flutter test` are clean across the whole client. The Postgres migration was **not** verified against a live database this session (no Docker daemon available in the environment) — run it against a real Postgres before shipping. **Update**: both screens have since had a live on-device tap-through by AmirAbbas — phone entry, custom keypad, OTP verify (via the `1111` dev bypass code, since no Kavenegar account is purchased yet), resend countdown, and both referral entry points (ZLogin teaser + Profile → Settings) were all exercised with no bugs found. Real SMS send/deliver through Kavenegar itself remains unverified end-to-end — that's blocked on purchasing a Kavenegar account, not a code gap.

---

## 6. Stage 5 — Secondary screens

- **ZBoard** ← `features/leaderboard/view/leaderboard_screen.dart` (693 ln) — three staggered podium pedestals, rank rows, sticky self-row on `inkSurface`. 4 tabs vs. spec's 2 → see conflict table.
- **ZProfile** ← `features/profile/view/profile_screen.dart` (789 ln) — 2×2 stat grid, level progress bar, badge row, settings list with the dark-mode toggle.
- **ZFriends** ← `features/friends/view/friends_screen.dart` (664 ln) — requests / online / offline sections, which map cleanly onto the existing cubit.

---

## 7. Stage 6 — Undesigned screens

`login_screen.dart`, `register_screen.dart`, `tutorial_screen.dart` (437 ln), and `continue_prompt.dart` have **no reference images** in the canvas.

Per `CLAUDE.md` ("if a detail is ambiguous, match the overall visual style and spacing of the nearest reference image"), derive these from the token system rather than inventing layouts.

---

## 8. Stage 7 — Tests

- Existing golden tests for `WordChainList` and `TimerBar` will break **by design** — re-baseline them.
- Add light + dark goldens for each shared widget in `core/widgets/`.
- Add a token-coverage check that fails on hardcoded `Color(0x…)` literals inside `features/`.

---

## 9. Open decisions — resolved

Both prior open items are settled (see §1 Decisions and the header note above): the six conflicts are decided, and Phase 17 is recorded in CLAUDE.md and PLAN.md.
