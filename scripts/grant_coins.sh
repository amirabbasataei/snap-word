#!/usr/bin/env bash
# Adds coins to users on the production database by phone number.
#
# Usage:
#   bash scripts/grant_coins.sh 500 09364419970                # +500 coins
#   bash scripts/grant_coins.sh 200 09364419970 09399040501    # +200 each
#   bash scripts/grant_coins.sh --dry-run 0 09364419970        # show balances only
#
# Phones are the normalized 09XXXXXXXXX form stored in users.phone.
# The app picks up the new balance the next time it loads the rewards screen
# (GET /rewards overwrites the local balance) or restarts.
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
DRY_RUN=false
ARGS=()

usage() { sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage 0 ;;
    -*) echo "Error: unknown option $a" >&2; usage 1 ;;
    *)  ARGS+=("$a") ;;
  esac
done

[[ ${#ARGS[@]} -ge 2 ]] || { echo "Error: give an amount and at least one phone number." >&2; usage 1; }
AMOUNT="${ARGS[0]}"
PHONES=("${ARGS[@]:1}")

[[ "$AMOUNT" =~ ^[0-9]+$ && "$AMOUNT" -le 100000 ]] \
  || { echo "Error: amount must be an integer between 0 and 100000." >&2; exit 1; }
$DRY_RUN || [[ "$AMOUNT" -ge 1 ]] || { echo "Error: amount must be at least 1." >&2; exit 1; }

# Strict validation also keeps the values safe to inline into SQL below.
for p in "${PHONES[@]}"; do
  [[ "$p" =~ ^09[0-9]{9}$ ]] || { echo "Error: '$p' is not a valid 09XXXXXXXXX phone number." >&2; exit 1; }
done

IN_LIST=$(printf "'%s'," "${PHONES[@]}")
IN_LIST="${IN_LIST%,}"

SHOW="SELECT username, phone, coins FROM users WHERE phone IN ($IN_LIST) ORDER BY phone;"
CHANGE="UPDATE users SET coins = coins + $AMOUNT WHERE phone IN ($IN_LIST);"

run_psql() {
  ssh "$HOST" "cd $REMOTE_DIR && docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U \$POSTGRES_USER -d \$POSTGRES_DB'"
}

echo "==> Host: $HOST   amount: +$AMOUNT$($DRY_RUN && echo "   (dry run)")"
echo "==> Before"
echo "$SHOW" | run_psql

if ! $DRY_RUN; then
  echo "==> Applying"
  echo "$CHANGE" | run_psql
  echo "==> After"
  echo "$SHOW" | run_psql
fi

echo "Note: a phone missing from the table above has not signed up yet — nothing was changed for it."
