#!/usr/bin/env bash
# Grants (or revokes) premium on the production database by phone number.
# Billing isn't built yet, so this is how premium is activated by hand.
#
# Usage:
#   bash scripts/grant_premium.sh 09364419970 09399040501        # +30 days each
#   bash scripts/grant_premium.sh -d 90 09364419970              # +90 days
#   bash scripts/grant_premium.sh --revoke 09364419970           # remove premium
#   bash scripts/grant_premium.sh --dry-run 09364419970          # show current state only
#
# Days are added on top of any remaining premium time (never shortens it).
# Phones are the normalized 09XXXXXXXXX form stored in users.phone.
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
DAYS=30
MODE="grant"
PHONES=()

usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--days)
      [[ $# -ge 2 ]] || { echo "Error: $1 needs a number." >&2; exit 1; }
      DAYS="$2"; shift 2 ;;
    --revoke)  MODE="revoke"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "Error: unknown option $1" >&2; usage 1 ;;
    *)  PHONES+=("$1"); shift ;;
  esac
done

[[ ${#PHONES[@]} -gt 0 ]] || { echo "Error: give at least one phone number." >&2; usage 1; }
[[ "$DAYS" =~ ^[0-9]+$ && "$DAYS" -ge 1 && "$DAYS" -le 3650 ]] \
  || { echo "Error: --days must be an integer between 1 and 3650." >&2; exit 1; }

# Strict validation also keeps the values safe to inline into SQL below.
for p in "${PHONES[@]}"; do
  [[ "$p" =~ ^09[0-9]{9}$ ]] || { echo "Error: '$p' is not a valid 09XXXXXXXXX phone number." >&2; exit 1; }
done

IN_LIST=$(printf "'%s'," "${PHONES[@]}")
IN_LIST="${IN_LIST%,}"

case "$MODE" in
  grant)
    CHANGE="UPDATE users
      SET premium_until = GREATEST(COALESCE(premium_until, now()), now()) + interval '$DAYS days'
      WHERE phone IN ($IN_LIST);" ;;
  revoke)
    CHANGE="UPDATE users SET premium_until = NULL WHERE phone IN ($IN_LIST);" ;;
  dry-run)
    CHANGE="" ;;
esac

SHOW="SELECT username, phone, premium_until, premium_until > now() AS is_premium
      FROM users WHERE phone IN ($IN_LIST) ORDER BY phone;"

echo "==> Host: $HOST   mode: $MODE$([[ $MODE == grant ]] && echo "   days: $DAYS")"

# Phones that don't exist are only reported afterwards (they have to sign up first).
run_psql() {
  ssh "$HOST" "cd $REMOTE_DIR && docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U \$POSTGRES_USER -d \$POSTGRES_DB'"
}

echo "==> Before"
echo "$SHOW" | run_psql

if [[ -n "$CHANGE" ]]; then
  echo "==> Applying"
  echo "$CHANGE" | run_psql
  echo "==> After"
  echo "$SHOW" | run_psql
fi

echo "Note: a phone missing from the table above has not signed up yet — nothing was changed for it."
