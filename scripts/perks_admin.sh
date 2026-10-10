#!/usr/bin/env bash
# Manages the premium taunt / avatar catalogues through the backend's admin API.
# Changes are live immediately — no app release, no redeploy.
#
# Usage:
#   bash scripts/perks_admin.sh list
#   bash scripts/perks_admin.sh taunt add <id> "<persian text>" [--order N]   # add, or edit the text
#   bash scripts/perks_admin.sh taunt rm  <id>
#   bash scripts/perks_admin.sh avatar add <id> <image.png|jpg|webp> [--order N]   # add, or replace the image
#   bash scripts/perks_admin.sh avatar rm  <id>       # users who picked it fall back to their initial
#   bash scripts/perks_admin.sh seed                  # upload scripts/seed/avatars/* (first deploy)
#
# ids: lowercase letters/digits/_, start with a letter (taunt ≤ 32 chars, avatar ≤ 24).
# Images: PNG/JPEG/WebP, ≤ 256 KB. Order is optional; new entries go last.
#
# By default the request runs ON the production host over SSH against the app's
# loopback port, with ADMIN_API_KEY read from /opt/wordchain/.env there — the key
# never crosses the network. (Add `ADMIN_API_KEY=<key>` to that .env and to the
# app's `environment:` in the server's compose file, then `docker compose up -d app`.)
# Local backend instead:
#   WORDCHAIN_API=http://localhost:8080 ADMIN_API_KEY=<key> bash scripts/perks_admin.sh list
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
REMOTE_PORT=18080
SEED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seed/avatars"
# Picker order of the original bundled avatars.
SEED_ORDER=(lion simorgh falcon fox owl cat horse dragon crown pen flame moon star diamond bolt rose)

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "Error: $*" >&2; exit 1; }

# call METHOD PATH [curl args…] — prints the body; fails on a non-2xx status.
# Only fixed, pre-validated tokens reach the remote shell (printf %q quotes them).
call() {
  local method=$1 path=$2; shift 2
  local out
  if [[ -n "${WORDCHAIN_API:-}" ]]; then
    out=$(curl -sS -X "$method" -H "X-Admin-Key: ${ADMIN_API_KEY:?set ADMIN_API_KEY}" \
      -w $'\n%{http_code}' "$@" "$WORDCHAIN_API$path")
  else
    local args; args=$(printf '%q ' "$@")
    out=$(ssh "$HOST" "cd $REMOTE_DIR && K=\$(grep -m1 '^ADMIN_API_KEY=' .env | cut -d= -f2-) \
      && [ -n \"\$K\" ] || { echo 'ADMIN_API_KEY missing from $REMOTE_DIR/.env' >&2; exit 3; }; \
      curl -sS -X $method -H \"X-Admin-Key: \$K\" -w '\n%{http_code}' $args http://127.0.0.1:$REMOTE_PORT$path")
  fi
  local code=${out##*$'\n'} body=${out%$'\n'*}
  echo "$body"
  [[ "$code" =~ ^2 ]] || die "HTTP $code"
}

valid_id() { [[ "$1" =~ ^[a-z][a-z0-9_]{1,23}$ || "$1" =~ ^[a-z][a-z0-9_]{1,31}$ ]] || die "bad id '$1'"; }

parse_order() { # sets ORDER (possibly empty) from trailing "--order N"
  ORDER=""
  if [[ "${1:-}" == "--order" ]]; then
    [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--order needs a number"
    ORDER=$2
  elif [[ -n "${1:-}" ]]; then
    die "unexpected argument '$1'"
  fi
}

avatar_add() { # id file [order]
  local id=$1 file=$2 order=${3:-}
  [[ -f "$file" ]] || die "no such file: $file"
  local type
  case "${file,,}" in
    *.png) type=image/png ;; *.jpg|*.jpeg) type=image/jpeg ;; *.webp) type=image/webp ;;
    *) die "image must be .png, .jpg or .webp" ;;
  esac
  local extra=()
  [[ -n "$order" ]] && extra=(-F "sort_order=$order")
  echo "==> avatar $id ← $(basename "$file")"
  if [[ -n "${WORDCHAIN_API:-}" ]]; then
    call PUT "/api/v1/admin/avatars/$id" -F "image=@$file;type=$type" "${extra[@]}"
  else
    # stdin carries the file to curl on the host
    call PUT "/api/v1/admin/avatars/$id" -F "image=@-;type=$type" "${extra[@]}" < "$file"
  fi
}

[[ $# -ge 1 ]] || usage 1
case "$1" in
  -h|--help) usage 0 ;;
  list)
    if [[ -n "${WORDCHAIN_API:-}" ]]; then
      curl -sS "$WORDCHAIN_API/api/v1/perks/catalog"
    else
      ssh "$HOST" "curl -sS http://127.0.0.1:$REMOTE_PORT/api/v1/perks/catalog"
    fi | python3 -m json.tool --no-ensure-ascii ;;
  taunt)
    case "${2:-}" in
      add)
        [[ $# -ge 4 ]] || usage 1
        valid_id "$3"; parse_order "${5:-}" "${6:-}"
        body=$(python3 -c 'import json,sys
d={"text":sys.argv[1]}
if sys.argv[2]: d["sort_order"]=int(sys.argv[2])
print(json.dumps(d,ensure_ascii=False))' "$4" "$ORDER")
        echo "$body" | call PUT "/api/v1/admin/taunts/$3" -H 'Content-Type: application/json' --data-binary @- ;;
      rm) [[ $# -eq 3 ]] || usage 1; valid_id "$3"; call DELETE "/api/v1/admin/taunts/$3" ;;
      *) usage 1 ;;
    esac ;;
  avatar)
    case "${2:-}" in
      add) [[ $# -ge 4 ]] || usage 1; valid_id "$3"; parse_order "${5:-}" "${6:-}"; avatar_add "$3" "$4" "$ORDER" ;;
      rm)  [[ $# -eq 3 ]] || usage 1; valid_id "$3"; call DELETE "/api/v1/admin/avatars/$3" ;;
      *) usage 1 ;;
    esac ;;
  seed)
    n=0
    for id in "${SEED_ORDER[@]}"; do
      n=$((n + 1))
      avatar_add "$id" "$SEED_DIR/$id.png" "$n"
    done ;;
  *) usage 1 ;;
esac
