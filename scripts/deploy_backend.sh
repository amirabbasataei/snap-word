#!/usr/bin/env bash
# Deploys backend/ to the production host and rebuilds the app container.
#
# Usage:
#   bash scripts/deploy_backend.sh             # sync + rebuild + health check
#   bash scripts/deploy_backend.sh --dry-run   # show what rsync would change
#   bash scripts/deploy_backend.sh --logs      # also tail the app logs afterwards
#
# Builds the admin panel (admin/ → backend/internal/adminui/dist, embedded in
# the Go binary) first, so the deployed image always carries a fresh panel.
# Syncs the working tree (committed or not). Server-only files (.env, compose
# files, secrets, the built binary) are never touched. Migrations run
# automatically at server startup.
# The panel is built for the public prefix PANEL_PREFIX (default /zanjir, i.e.
# https://amirabbasataei.ir/zanjir/admin); nginx strips it (scripts/nginx/zanjir.conf).
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
HEALTH_URL="http://185.110.191.158:8080/health"
export PANEL_PREFIX="${PANEL_PREFIX-/zanjir}"
DRY_RUN=false
TAIL_LOGS=false

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=true ;;
    --logs) TAIL_LOGS=true ;;
    -h|--help) usage 0 ;;
    *) echo "Error: unknown option $a" >&2; usage 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Building admin panel (pnpm -C admin build)"
pnpm -C admin install --frozen-lockfile
pnpm -C admin build

echo "==> Vetting backend (go build)"
(cd backend && go build ./... )

RSYNC=(rsync -a --exclude /server --exclude /.env --exclude /secrets
       --exclude 'docker-compose*.yml' --exclude '*.md')

if $DRY_RUN; then
  echo "==> Dry run: files rsync would transfer"
  "${RSYNC[@]}" -i --dry-run backend/ "$HOST:$REMOTE_DIR/"
  exit 0
fi

echo "==> Syncing backend/ to $HOST:$REMOTE_DIR"
"${RSYNC[@]}" backend/ "$HOST:$REMOTE_DIR/"

echo "==> Rebuilding and restarting app"
ssh "$HOST" "cd $REMOTE_DIR && docker compose up -d --build app"

echo "==> Waiting for health check"
for i in $(seq 1 30); do
  if curl -fsS -m 3 "$HEALTH_URL" >/dev/null 2>&1; then
    echo "OK: backend is up ($HEALTH_URL)"
    $TAIL_LOGS && exec ssh "$HOST" "cd $REMOTE_DIR && docker compose logs -f --tail 50 app"
    exit 0
  fi
  sleep 2
done

echo "Error: backend did not become healthy in 60s. Recent logs:" >&2
ssh "$HOST" "cd $REMOTE_DIR && docker compose logs --tail 40 app" >&2
exit 1
