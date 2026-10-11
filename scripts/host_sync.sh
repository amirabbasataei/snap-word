#!/usr/bin/env bash
# Pushes deploy/host (shared Postgres, nginx, timers, new-site & co.) to the
# server's /opt/infra and applies it with /opt/infra/install.sh.
#
#   bash scripts/host_sync.sh             # sync + install
#   bash scripts/host_sync.sh --dry-run   # show what would change
#
# Server-only state is never overwritten: /opt/infra/.env (Postgres superuser
# password), /opt/infra/ports (port registry), post-backup.d hooks you enabled.
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).
set -euo pipefail
HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RSYNC=(rsync -rlptz --chmod=go-rwx --exclude /.env --exclude /ports --exclude '/post-backup.d/*.sh')
if [[ "${1:-}" == --dry-run ]]; then
  "${RSYNC[@]}" -i --dry-run "$ROOT/deploy/host/" "$HOST:/opt/infra/"; exit 0
fi
"${RSYNC[@]}" "$ROOT/deploy/host/" "$HOST:/opt/infra/"
ssh "$HOST" /opt/infra/install.sh
