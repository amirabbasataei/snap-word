#!/usr/bin/env bash
# Creates and maintains admin panel accounts on the production host.
#
# Usage:
#   bash scripts/admin_user.sh <username> [owner|operator|viewer]   # create (default role: owner)
#   bash scripts/admin_user.sh --set-password <username>
#   bash scripts/admin_user.sh --disable <username>
#   bash scripts/admin_user.sh --enable  <username>
#
# Runs /adminctl inside the app container over SSH with a TTY, so the password
# is typed into adminctl's own no-echo prompt on the server — it never appears in
# argv, shell history or the process list. Passwords: 10-72 characters.
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "Error: $*" >&2; exit 1; }

case "${1:-}" in
  ""|-h|--help) usage ;;
  --set-password) cmd=set-password; shift ;;
  --disable)      cmd=disable;      shift ;;
  --enable)       cmd=enable;       shift ;;
  -*)             die "unknown flag $1" ;;
  *)              cmd=create-user ;;
esac

user="${1:-}"; role="${2:-}"
[[ "$user" =~ ^[a-z][a-z0-9_.-]{2,31}$ ]] || die "username must be 3-32 chars: lowercase letter first, then letters, digits, _ . -"
if [[ -n "$role" ]]; then
  [[ "$cmd" == create-user ]] || die "a role only applies when creating a user"
  [[ "$role" =~ ^(owner|operator|viewer)$ ]] || die "role must be owner, operator or viewer"
fi

# user and role are validated above, so they are safe to put in the remote command line.
ssh -t "$HOST" "cd $REMOTE_DIR && docker compose exec app /adminctl $cmd $user $role"
