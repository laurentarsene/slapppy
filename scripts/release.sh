#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  release.sh — Build · Sign · Notarise · DMG · Staple
#
#  Run from the repo root:
#    ./scripts/release.sh
#
#  Prerequisites
#  ─────────────────────────────────────────────────────────────────
#  1. Apple Developer account active (developer.apple.com)
#  2. "Developer ID Application" certificate in your Keychain
#     (Xcode → Settings → Accounts → Manage Certificates)
#  3. App-specific password created at appleid.apple.com
#     (Sign-in & Security → App-Specific Passwords)
#  4. Your Team ID — visible at developer.apple.com/account (top right)
#
#  Set these three env vars before running:
#    export APPLE_ID="you@example.com"
#    export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#    export TEAM_ID="XXXXXXXXXX"
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────
SCHEME="Slappy"
PROJECT="Slappy/Slappy.xcodeproj"
APP_VERSION="1.0"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Slapppy.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Slappy.app"
DMG_PATH="$BUILD_DIR/Slapppy-$APP_VERSION.dmg"

# Credentials — prefer env vars; fall back to the placeholders below
APPLE_ID="${APPLE_ID:-REPLACE_WITH_YOUR_APPLE_ID}"
APP_PASSWORD="${APP_PASSWORD:-REPLACE_WITH_APP_SPECIFIC_PASSWORD}"
TEAM_ID="${TEAM_ID:-REPLACE_WITH_TEAM_ID}"

# ── Sanity checks ─────────────────────────────────────────────────
if [[ "$APPLE_ID" == REPLACE* ]] || [[ "$APP_PASSWORD" == REPLACE* ]] || [[ "$TEAM_ID" == REPLACE* ]]; then
  echo "❌  Set APPLE_ID, APP_PASSWORD and TEAM_ID before running."
  echo "    export APPLE_ID=\"you@example.com\""
  echo "    export APP_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
  echo "    export TEAM_ID=\"XXXXXXXXXX\""
  exit 1
fi

mkdir -p "$BUILD_DIR"

# ── 1. Archive ────────────────────────────────────────────────────
echo ""
echo "▶ 1/5  Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  2>&1 | grep -E "^(Build|error:|warning: |✓|▶)" || true

echo "   Archive: $ARCHIVE_PATH"

# ── 2. Export (Developer ID) ──────────────────────────────────────
echo ""
echo "▶ 2/5  Exporting with Developer ID signing..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "scripts/ExportOptions.plist" \
  2>&1 | grep -E "^(error:|warning: |✓)" || true

echo "   App: $APP_PATH"

# ── 3. Create DMG ─────────────────────────────────────────────────
echo ""
echo "▶ 3/5  Creating DMG..."
rm -f "$DMG_PATH"

STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Slapppy $APP_VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" > /dev/null

rm -rf "$STAGING"
echo "   DMG: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── 4. Notarise ───────────────────────────────────────────────────
echo ""
echo "▶ 4/5  Notarising (this takes 1–5 minutes)..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id  "$APPLE_ID" \
  --password  "$APP_PASSWORD" \
  --team-id   "$TEAM_ID" \
  --wait \
  --verbose 2>&1 | grep -E "(status:|message:|id:)" || true

# ── 5. Staple ─────────────────────────────────────────────────────
echo ""
echo "▶ 5/5  Stapling notarisation ticket..."
xcrun stapler staple "$DMG_PATH"

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "✅  Done!"
echo "   File: $DMG_PATH"
echo "   → Upload this file to LemonSqueezy as the product file."
echo ""
