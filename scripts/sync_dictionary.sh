#!/usr/bin/env bash
# Folds the admin-approved dictionary changes into fa.txt.
#
# Fetches GET /api/v1/admin/dictionary/export (words added / removed since fa.txt
# was built), adds the `added` words to both fa.txt copies, deletes the `removed`
# ones, and keeps the file sorted (code-point order, like the rest of the file).
# `ai_blocked` words are ignored: they stay in fa.txt and in the server overlay.
# Idempotent — running it twice changes nothing the second time.
#
# Usage:
#   bash scripts/sync_dictionary.sh              # fetch from production over SSH, rewrite both files
#   bash scripts/sync_dictionary.sh --dry-run    # show what would change, write nothing
#
# After it changes something: review `git diff`, then redeploy the backend
# (bash scripts/deploy_backend.sh) and ship a new app build. Once the new binary
# is live the export becomes empty (the words are now "in the base list").
#
# Like perks_admin.sh, the request runs ON the production host over SSH against
# the app's loopback port; ADMIN_API_KEY is read from /opt/wordchain/.env there
# and never crosses the network. Local backend instead:
#   WORDCHAIN_API=http://localhost:8080 ADMIN_API_KEY=<key> bash scripts/sync_dictionary.sh
# Override the host with WORDCHAIN_HOST (default root@185.110.191.158).

set -euo pipefail

HOST="${WORDCHAIN_HOST:-root@185.110.191.158}"
REMOTE_DIR="/opt/wordchain"
REMOTE_PORT=18080
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=("$ROOT/backend/internal/engine/data/fa.txt" "$ROOT/client/assets/words/fa.txt")
PATH_API="/api/v1/admin/dictionary/export"

DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Error: unknown argument '$1'" >&2; exit 1 ;;
esac

die() { echo "Error: $*" >&2; exit 1; }

for f in "${FILES[@]}"; do [[ -f "$f" ]] || die "missing $f"; done
cmp -s "${FILES[0]}" "${FILES[1]}" || die "the two fa.txt copies differ — fix that first (they must be byte-identical)"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [[ -n "${WORDCHAIN_API:-}" ]]; then
  out=$(curl -sS -H "X-Admin-Key: ${ADMIN_API_KEY:?set ADMIN_API_KEY}" \
    -w $'\n%{http_code}' "$WORDCHAIN_API$PATH_API")
else
  out=$(ssh "$HOST" "cd $REMOTE_DIR && K=\$(grep -m1 '^ADMIN_API_KEY=' .env | cut -d= -f2-) \
    && [ -n \"\$K\" ] || { echo 'ADMIN_API_KEY missing from $REMOTE_DIR/.env' >&2; exit 3; }; \
    curl -sS -H \"X-Admin-Key: \$K\" -w '\n%{http_code}' http://127.0.0.1:$REMOTE_PORT$PATH_API")
fi
code=${out##*$'\n'}
[[ "$code" =~ ^2 ]] || die "export request failed: HTTP $code"
printf '%s' "${out%$'\n'*}" > "$TMP"

# -I: isolated mode (no cwd / env-driven imports). Paths are arguments, not code.
python3 -I - "$TMP" "$DRY" "${FILES[@]}" <<'PY'
import json, re, sys

export_path, dry, *files = sys.argv[1:]
dry = dry == "1"

try:
    data = json.load(open(export_path, encoding="utf-8"))["data"]
    added, removed = data["added"], data["removed"]
except (ValueError, KeyError, TypeError) as e:
    sys.exit(f"Error: unexpected export response ({e})")

# Persian letters + ZWNJ only, same shape the server accepts. Anything else in the
# response is refused rather than written into the dictionary.
ok = re.compile(r"^[ء-غف-يپچژکگی‌]{2,}$")
for w in added + removed:
    if not ok.match(w):
        sys.exit(f"Error: refusing suspicious word {w!r} from the export")

path = files[0]
raw = open(path, encoding="utf-8").read()
words = raw.split("\n")
if words and words[-1] == "":
    words.pop()
cur = set(words)

to_add = sorted(w for w in set(added) if w not in cur)
to_del = sorted(w for w in set(removed) if w in cur)

print(f"export: {len(added)} added, {len(removed)} removed (seq {data.get('seq')})")
print(f"fa.txt: {len(words)} words -> +{len(to_add)} new, -{len(to_del)} removed")
for w in to_add:
    print(f"  + {w}")
for w in to_del:
    print(f"  - {w}")

if not to_add and not to_del:
    print("Nothing to do.")
    sys.exit(0)
if dry:
    print("Dry run: no files written.")
    sys.exit(0)

new = sorted((cur | set(to_add)) - set(to_del))  # code-point order == UTF-8 byte order
text = "\n".join(new) + "\n"
for f in files:
    with open(f, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
print(f"Wrote {len(new)} words to {len(files)} files. Review `git diff`, then redeploy the backend and ship a client build.")
PY
