#!/usr/bin/env bash
# Builds app-arm64-v8a-release.apk, copies it to output/, and pushes to GitHub.
# Requirements: Flutter SDK, Android SDK, git configured with push access.
# Usage: bash scripts/build_apk.sh [--no-push]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$REPO_ROOT/client"
OUTPUT_DIR="$REPO_ROOT/output"
APK_NAME="app-arm64-v8a-release.apk"
BUILT_APK="$CLIENT_DIR/build/app/outputs/flutter-apk/$APK_NAME"

NO_PUSH=false
if [[ "${1:-}" == "--no-push" ]]; then
  NO_PUSH=true
fi

echo "==> Checking requirements..."
command -v flutter >/dev/null 2>&1 || { echo "Error: flutter not found in PATH."; exit 1; }
command -v git    >/dev/null 2>&1 || { echo "Error: git not found in PATH.";    exit 1; }

echo "==> Running flutter pub get..."
cd "$CLIENT_DIR"
flutter pub get

echo "==> Running build_runner (Drift codegen)..."
dart run build_runner build --delete-conflicting-outputs

echo "==> Building split-per-ABI release APKs..."
flutter build apk --split-per-abi --release

if [[ ! -f "$BUILT_APK" ]]; then
  echo "Error: Expected APK not found at $BUILT_APK"
  exit 1
fi

echo "==> Copying $APK_NAME to output/..."
mkdir -p "$OUTPUT_DIR"
cp "$BUILT_APK" "$OUTPUT_DIR/$APK_NAME"

VERSION=$(grep '^version:' "$CLIENT_DIR/pubspec.yaml" | awk '{print $2}')
SIZE_MB=$(du -sh "$OUTPUT_DIR/$APK_NAME" | cut -f1)
echo "==> APK ready: output/$APK_NAME  ($SIZE_MB)  version $VERSION"

if [[ "$NO_PUSH" == true ]]; then
  echo "==> Skipping git push (--no-push)."
  exit 0
fi

echo "==> Committing and pushing to GitHub..."
cd "$REPO_ROOT"
git add "output/$APK_NAME"
git commit -m "release: update $APK_NAME to v$VERSION"
git push

echo "==> Done. Download URL:"
REMOTE=$(git remote get-url origin)
# Convert SSH remote (git@github.com:user/repo.git) to HTTPS URL
if [[ "$REMOTE" == git@github.com:* ]]; then
  REPO_PATH="${REMOTE#git@github.com:}"
  REPO_PATH="${REPO_PATH%.git}"
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "    https://github.com/$REPO_PATH/raw/$BRANCH/output/$APK_NAME"
else
  echo "    $REMOTE  →  output/$APK_NAME"
fi
