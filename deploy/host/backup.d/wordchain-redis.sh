#!/usr/bin/env bash
# Adds Zanjir's Redis snapshot (weekly leaderboard, admin sessions) to the backup.
set -euo pipefail
c=wordchain-redis-1
docker ps --format '{{.Names}}' | grep -qx "$c" || exit 0
docker exec "$c" redis-cli SAVE >/dev/null
docker cp "$c:/data/dump.rdb" "$BACKUP_DIR/wordchain-redis.rdb"
