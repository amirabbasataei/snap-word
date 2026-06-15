# SnapWord — WordChain Game

A production-ready **Shiritori-style word chain** mobile game for Android.  
Chain words together: each new word must start with the last letter of the previous one.

---

## Download (Android)

> **Requires Android 5.0+ · arm64-v8a device (most phones since 2015)**

[**⬇ Download latest APK**](output/app-arm64-v8a-release.apk)

Or install via `adb`:
```bash
adb install output/app-arm64-v8a-release.apk
```

---

## Features

- **Classic mode** — first invalid word or timeout loses; one continue per player
- **Time Attack** — 90-second race, highest score wins
- **Daily Challenge** — solo-only, once per day, score posted to global leaderboard
- **vs AI** — Easy / Medium / Hard opponents with adaptive strategy
- **1v1 Real-time multiplayer** — shared word chain over WebSocket
- **Power-ups** — Hint, Freeze, Extra Time, Shield
- **Friends & challenges** — send match invites to friends
- **Leaderboard** — global + friends; weekly rewards
- **Daily streak** — track consecutive play days, earn milestone coins
- **Offline-first** — Solo and AI games work with no internet connection
- **Guest mode** — play immediately, no sign-up required

---

## Game Rules

1. Enter any valid English word (≥ 3 letters) to start the chain.
2. Each subsequent word must begin with the **last letter** of the previous word.
3. No repeating words.
4. Words are validated against the ENABLE dictionary (~172 000 words).
5. Classic: 15-second turn timer. Time Attack: 8-second timer, 90-second match.

---

## Build from Source

### Requirements

- Flutter 3.32+
- Android SDK (API 21+)
- Dart 3.7+

### Steps

```bash
git clone git@github.com:amirabbasataei/snap-word.git
cd snap-word/client
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --split-per-abi --release
# APK at: client/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### Build & publish script

The `scripts/build_apk.sh` script builds the APK, copies it to `output/`, and pushes it to GitHub in one command:

```bash
# build + push
bash scripts/build_apk.sh

# build only (skip git push)
bash scripts/build_apk.sh --no-push
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter + flutter_bloc + go_router |
| Backend | Go · Gin · WebSocket |
| Database | PostgreSQL 16 · Redis 7 |
| Local DB | Drift (SQLite) |
| Auth | JWT (access + refresh) |
| Push | Firebase Cloud Messaging |

---

## License

MIT
