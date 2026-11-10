# local-database

> Moved verbatim out of CLAUDE.md on 2026-11-10 to keep that file under the size limit. CLAUDE.md keeps a short summary and links here.

## 📱 Local Database Schema (Flutter / Drift)

All tables live in a single Drift database (`AppDatabase`) at `core/database/app_database.dart`. Schema version starts at `1`; increment and add a `MigrationStrategy` step on every change. Run `dart run build_runner build` after schema edits.

```dart
class LocalMatches extends Table {
  IntColumn     get id           => integer().autoIncrement()();
  TextColumn    get remoteId     => text().nullable()();         // null until synced
  TextColumn    get mode         => text()();                    // classic
  TextColumn    get opponentType => text()();                    // solo | ai_easy | ai_medium | ai_hard
  TextColumn    get status       => text()();                    // active | finished | abandoned
  IntColumn     get score        => integer().withDefault(const Constant(0))();
  IntColumn     get chainLength  => integer().withDefault(const Constant(0))();
  TextColumn    get wordChain    => text().withDefault(const Constant('[]'))(); // JSON List<String>
  BoolColumn    get synced       => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startedAt   => dateTime()();
  DateTimeColumn get endedAt     => dateTime().nullable()();
  TextColumn    get scoreTrace   => text().nullable()();         // v3: per-word times + streaks (Daily upload), see § Daily fairness
}

class LocalUsedWords extends Table {
  IntColumn  get matchId => integer()();   // FK → LocalMatches.id
  TextColumn get word    => text()();
  @override
  Set<Column> get primaryKey => {matchId, word};
}

class LocalPlayerStats extends Table {
  IntColumn     get id                 => integer().withDefault(const Constant(1))();
  IntColumn     get totalMatches       => integer().withDefault(const Constant(0))();
  IntColumn     get wins               => integer().withDefault(const Constant(0))();
  IntColumn     get bestScore          => integer().withDefault(const Constant(0))();
  IntColumn     get bestMatchStreak    => integer().withDefault(const Constant(0))();
  IntColumn     get dailyStreak        => integer().withDefault(const Constant(0))();
  IntColumn     get longestDailyStreak => integer().withDefault(const Constant(0))();
  TextColumn    get longestWord        => text().nullable()();
  DateTimeColumn get lastPlayedDate    => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class LocalPowerupCache extends Table {
  TextColumn     get powerupType  => text()();                    // hint | extra_time | shield (freeze removed 2026-11-10)
  IntColumn      get quantity     => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {powerupType};
}
```

### DAO responsibilities

| DAO | Key methods |
|---|---|
| `MatchDao` | `createMatch`, `updateMatch`, `getActiveMatch`, `getUnsyncedMatches`, `markSynced(id, remoteId)` |
| `UsedWordDao` | `insertWord(matchId, word)`, `isWordUsed(matchId, word) → bool`, `deleteWordsForMatch(matchId)` |
| `StatsDao` | `getStats`, `upsertStats`, `mergeWithRemote(RemoteStats)` — takes MAX of each numeric field |
| `PowerupCacheDao` | `getAll`, `setQuantity(type, qty)`, `refreshFromRemote(List<RemotePowerup>)` |

### Sync strategy (`SyncService`)

```
SyncService.sync()  ← idempotent; no-op if guest; safe to call on every app resume
  1. Upload unsynced matches
       fetch local_matches WHERE synced = false, ORDER BY startedAt ASC
       → POST /api/v1/game/solo for each
       → 200: set synced = true, store remoteId
       → 409 (already exists): mark synced = true silently
       → network error: abort remaining; retry on next trigger
  2. Merge stats
       GET /api/v1/profile/stats → StatsDao.mergeWithRemote()
  3. Refresh powerup cache
       GET /api/v1/powerup/inventory → PowerupCacheDao.refreshFromRemote()
```

**Sync triggers:** app foreground (authenticated), successful registration/login, connectivity restored, before joining multiplayer queue.

---
