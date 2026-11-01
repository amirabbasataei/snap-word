#!/usr/bin/env bash
# Builds the release App Bundle and signs it into the .bin file Cafe Bazaar asks
# for (cafebazaar/bundle-signer, `genbin`). Works on Linux and macOS.
#
#   bash scripts/bazaar_bundle_bin.sh              # build the .aab, then the .bin
#   bash scripts/bazaar_bundle_bin.sh --skip-build # reuse the existing .aab
#
# Needs: Java 11+ (macOS: `brew install openjdk@17`), curl, Flutter, and
# client/android/key.properties pointing at the release keystore.
#
# Overrides (environment):
#   KEYSTORE=/path/to/zanjir-release.jks   if the keystore is somewhere else than
#                                          key.properties says (typical on a 2nd machine)
#   BUNDLESIGNER_JAR=/path/to/jar          use a jar you already have
#   OUT_DIR=/some/dir                      where the .bin is written (default: next to the .aab)
set -euo pipefail

VERSION="0.1.14"
JAR_URL="https://github.com/cafebazaar/bundle-signer/releases/download/v${VERSION}/bundlesigner-${VERSION}.jar"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/client"
PROPS="$CLIENT/android/key.properties"
AAB_DIR="$CLIENT/build/app/outputs/bundle/release"
AAB="$AAB_DIR/app-release.aab"
OUT_DIR="${OUT_DIR:-$AAB_DIR}"
JAR="${BUNDLESIGNER_JAR:-$HOME/tools/bundlesigner-${VERSION}.jar}"

skip_build=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=true ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

command -v java >/dev/null || die "Java not found. Linux: install a JDK; macOS: brew install openjdk@17 (then follow brew's 'sudo ln -sfn …' hint)."
[ -f "$PROPS" ] || die "$PROPS is missing. Copy it (and the .jks) from the machine that has them; see client/android/key.properties.example."

prop() { grep "^$1=" "$PROPS" | head -n1 | cut -d= -f2-; }
KS_PASS="$(prop storePassword)"
KEY_PASS="$(prop keyPassword)"
KEY_ALIAS="$(prop keyAlias)"
KS_FILE="${KEYSTORE:-$(prop storeFile)}"
KS_FILE="${KS_FILE/#\~/$HOME}"

[ -n "$KS_PASS" ] && [ -n "$KEY_ALIAS" ] || die "storePassword/keyAlias missing in key.properties"
[ -f "$KS_FILE" ] || die "keystore not found: $KS_FILE (set KEYSTORE=/path/to/zanjir-release.jks)"

if [ ! -f "$JAR" ]; then
  echo "Downloading bundle-signer ${VERSION} (~31 MB) to $JAR"
  mkdir -p "$(dirname "$JAR")"
  curl -fL --retry 3 -o "$JAR.part" "$JAR_URL"
  mv "$JAR.part" "$JAR"
fi

if [ "$skip_build" = false ]; then
  (cd "$CLIENT" && flutter build appbundle --release)
fi
[ -f "$AAB" ] || die "$AAB not found (run without --skip-build)"

mkdir -p "$OUT_DIR"
# A stale .bin from an older build must never be uploaded by mistake.
rm -f "$OUT_DIR"/*.bin

# Passwords go through the environment, never argv, so they stay out of `ps`
# and shell history.
export BUNDLE_KS_PASS="$KS_PASS" BUNDLE_KEY_PASS="${KEY_PASS:-$KS_PASS}"
java -jar "$JAR" genbin \
  --bundle "$AAB" \
  --bin "$OUT_DIR" \
  --v2-signing-enabled true --v3-signing-enabled true \
  --ks "$KS_FILE" --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:BUNDLE_KS_PASS --key-pass env:BUNDLE_KEY_PASS

bin_files=("$OUT_DIR"/*.bin)
[ -e "${bin_files[0]}" ] || die "genbin finished but produced no .bin in $OUT_DIR"

echo
echo "Upload to Cafe Bazaar:"
echo "  bundle: $AAB"
for f in "${bin_files[@]}"; do echo "  bin:    $f"; done
