#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  ship.sh — One command to release a new version of Slapppy
#
#  Usage:
#    ./scripts/ship.sh <version>
#
#  Example:
#    ./scripts/ship.sh 1.1
#
#  Credentials are read from .env.local at the repo root (gitignored).
#  Create it once:
#
#    cat > .env.local <<EOF
#    APPLE_ID="you@example.com"
#    APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#    TEAM_ID="XXXXXXXXXX"
#    EOF
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "❌  Usage: ./scripts/ship.sh <version>  (e.g. 1.1)"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.local"
RELEASE_SH="$REPO_ROOT/scripts/release.sh"
DMG_NAME="Slapppy-$VERSION.dmg"
DMG_PATH="$REPO_ROOT/build/$DMG_NAME"

# ── Load credentials from .env.local ──────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  echo "❌  No .env.local found. Create it:"
  echo ""
  echo "    cat > .env.local <<EOF"
  echo "    APPLE_ID=\"you@example.com\""
  echo "    APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
  echo "    TEAM_ID=\"XXXXXXXXXX\""
  echo "    EOF"
  exit 1
fi

export APPLE_ID APP_PASSWORD TEAM_ID
export DOWNLOAD_BASE_URL="https://github.com/laurentarsene/slapppy/releases/download/v$VERSION"

# ── Bump version + build number in release.sh ─────────────────────
CURRENT_VERSION=$(grep '^APP_VERSION=' "$RELEASE_SH" | cut -d'"' -f2)
CURRENT_BUILD=$(grep '^BUILD_NUMBER=' "$RELEASE_SH" | cut -d'"' -f2)
NEW_BUILD=$(( CURRENT_BUILD + 1 ))

echo ""
echo "🚀  Shipping Slapppy $VERSION (build $NEW_BUILD)"
echo "    (was $CURRENT_VERSION, build $CURRENT_BUILD)"
echo ""

sed -i '' "s/^APP_VERSION=.*/APP_VERSION=\"$VERSION\"/" "$RELEASE_SH"
sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=\"$NEW_BUILD\"/" "$RELEASE_SH"

# ── Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in pbxproj ───
PBXPROJ="$REPO_ROOT/Slappy/Slappy.xcodeproj/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" "$PBXPROJ"

# ── Run release.sh (archive, sign, DMG, notarise, staple, appcast) ─
cd "$REPO_ROOT"
bash "$RELEASE_SH"

# ── Create GitHub Release and upload DMG ──────────────────────────
echo ""
echo "▶  Creating GitHub Release v$VERSION..."
gh release create "v$VERSION" "$DMG_PATH" \
  --title "Slapppy $VERSION" \
  --notes "Slapppy $VERSION" \
  --latest

echo "   GitHub Release: https://github.com/laurentarsene/slapppy/releases/tag/v$VERSION"

# ── Commit and push updated appcast.xml ───────────────────────────
echo ""
echo "▶  Pushing appcast.xml..."
git add docs/appcast.xml scripts/release.sh
git commit -m "release $VERSION"
git push

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "✅  Slapppy $VERSION is live!"
echo "   Appcast: https://laurentarsene.github.io/slapppy/appcast.xml"
echo "   Release: https://github.com/laurentarsene/slapppy/releases/tag/v$VERSION"
echo ""
