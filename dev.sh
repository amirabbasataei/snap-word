#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/backend" && pwd)"

start() {
  echo "==> Starting PostgreSQL..."
  if pg_isready -h localhost -p 5432 -q; then
    echo "    Already running."
  else
    sudo pg_ctlcluster 14 main start
  fi

  echo "==> Starting Redis..."
  if redis-cli ping -q 2>/dev/null | grep -q PONG; then
    echo "    Already running."
  else
    redis-server --daemonize yes --logfile /tmp/redis-wordchain.log --port 6379
  fi

  echo "==> Running backend..."
  cd "$BACKEND_DIR"
  set -o allexport
  # shellcheck source=backend/.env
  source "$BACKEND_DIR/.env"
  set +o allexport
  go run ./cmd/server/
}

stop() {
  echo "==> Stopping Redis..."
  redis-cli shutdown 2>/dev/null && echo "    Done." || echo "    Not running."

  echo "==> Stopping PostgreSQL..."
  sudo pg_ctlcluster 14 main stop
}

case "${1:-start}" in
  start) start ;;
  stop)  stop  ;;
  *)
    echo "Usage: $0 [start|stop]"
    exit 1
    ;;
esac
