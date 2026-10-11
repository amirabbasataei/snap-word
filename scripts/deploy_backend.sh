#!/usr/bin/env bash
# Builds the backend image locally and ships it to the production host.
#
# Usage:
#   bash scripts/deploy_backend.sh             # build + ship + restart + health check
#   bash scripts/deploy_backend.sh --dry-run   # build only; show the tag and compose diff
#   bash scripts/deploy_backend.sh --logs      # also tail the app logs afterwards
#
# Steps: build the admin panel (admin/ → backend/internal/adminui/dist, embedded
# in the binary) → go build vet → docker build (linux/amd64) → docker save | ssh
# docker load → sync deploy/sites/wordchain/compose.yml → set APP_IMAGE in the
# server's .env → docker compose up -d → health check. The server never builds
# images (1 vCPU / 2 GB). Migrations run at startup. Secrets stay in the
# server's root-only /opt/wordchain/.env. The previous image is kept for rollback:
#   ssh HOST "sed -i 's|^APP_IMAGE=.*|APP_IMAGE=wordchain-app:<old tag>|' /opt/wordchain/.env \
#             && cd /opt/wordchain && docker compose up -d app"
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
DRY_RUN=false
TAIL_LOGS=false

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

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

TAG="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- backend admin || echo -dirty)-$(date +%m%d%H%M)"
IMAGE="wordchain-app:$TAG"

echo "==> Building admin panel"
pnpm -C admin install --frozen-lockfile
pnpm -C admin build

echo "==> Vetting backend (go build)"
(cd backend && go build ./... )

echo "==> Building image $IMAGE"
docker build --platform linux/amd64 -t "$IMAGE" backend

if $DRY_RUN; then
  echo "==> Dry run: built $IMAGE; compose changes on the server:"
  ssh "$HOST" "cat $REMOTE_DIR/compose.yml 2>/dev/null" | diff - deploy/sites/wordchain/compose.yml || true
  exit 0
fi

echo "==> Shipping image ($(docker image inspect -f '{{.Size}}' "$IMAGE" | numfmt --to=iec))"
docker save "$IMAGE" | gzip -1 | ssh "$HOST" 'gunzip | docker load -q'

echo "==> Restarting app"
scp -q deploy/sites/wordchain/compose.yml "$HOST:$REMOTE_DIR/compose.yml"
ssh "$HOST" "set -e; cd $REMOTE_DIR
  if grep -q '^APP_IMAGE=' .env; then sed -i 's|^APP_IMAGE=.*|APP_IMAGE=$IMAGE|' .env; else echo 'APP_IMAGE=$IMAGE' >> .env; fi
  docker compose up -d --remove-orphans app
  # keep the three newest images for rollback
  docker images wordchain-app --format '{{.CreatedAt}} {{.Repository}}:{{.Tag}}' | sort -r | tail -n +4 | awk '{print \$NF}' | xargs -r docker rmi -f >/dev/null 2>&1 || true"

echo "==> Waiting for health check"
for _ in $(seq 1 30); do
  if ssh "$HOST" "curl -fsS -m 3 http://127.0.0.1:18080/health" >/dev/null 2>&1; then
    echo "OK: $IMAGE is up"
    $TAIL_LOGS && exec ssh "$HOST" "cd $REMOTE_DIR && docker compose logs -f --tail 50 app"
    exit 0
  fi
  sleep 2
done

echo "Error: backend did not become healthy in 60s. Recent logs:" >&2
ssh "$HOST" "cd $REMOTE_DIR && docker compose logs --tail 40 app" >&2
exit 1
