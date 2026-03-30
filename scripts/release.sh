#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  release.sh — Build · Sign · Notarise · DMG · Staple · Appcast
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
#  5. Sparkle EdDSA private key in Keychain (generated once with generate_keys)
#  6. DOWNLOAD_BASE_URL: public URL where you host the DMG
#
#  Set these env vars before running:
#    export APPLE_ID="you@example.com"
#    export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#    export TEAM_ID="XXXXXXXXXX"
#    export DOWNLOAD_BASE_URL="https://github.com/laurentarsene/slapppy/releases/download/v1.0"
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────
SCHEME="Slappy"
PROJECT="Slappy/Slappy.xcodeproj"
APP_VERSION="1.9"
BUILD_NUMBER="11"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Slapppy.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Slappy.app"
DMG_NAME="Slapppy-$APP_VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
APPCAST_PATH="docs/appcast.xml"
SIGN_UPDATE="/tmp/sparkle/bin/sign_update"

# Credentials — prefer env vars; fall back to the placeholders below
APPLE_ID="${APPLE_ID:-REPLACE_WITH_YOUR_APPLE_ID}"
APP_PASSWORD="${APP_PASSWORD:-REPLACE_WITH_APP_SPECIFIC_PASSWORD}"
TEAM_ID="${TEAM_ID:-REPLACE_WITH_TEAM_ID}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-REPLACE_WITH_DOWNLOAD_BASE_URL}"

# ── Sanity checks ─────────────────────────────────────────────────
if [[ "$APPLE_ID" == REPLACE* ]] || [[ "$APP_PASSWORD" == REPLACE* ]] || [[ "$TEAM_ID" == REPLACE* ]]; then
  echo "❌  Set APPLE_ID, APP_PASSWORD and TEAM_ID before running."
  exit 1
fi

if [[ "$DOWNLOAD_BASE_URL" == REPLACE* ]]; then
  echo "❌  Set DOWNLOAD_BASE_URL before running."
  echo "    export DOWNLOAD_BASE_URL=\"https://github.com/laurentarsene/slapppy/releases/download/v$APP_VERSION\""
  exit 1
fi

if [[ ! -f "$SIGN_UPDATE" ]]; then
  echo "❌  Sparkle sign_update not found at $SIGN_UPDATE"
  echo "    Run: curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.0/Sparkle-2.9.0.tar.xz && mkdir -p /tmp/sparkle && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle"
  exit 1
fi

mkdir -p "$BUILD_DIR"
# Remove stale build artefacts so failures can never silently reuse old files
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# ── 1. Archive ────────────────────────────────────────────────────
echo ""
echo "▶ 1/6  Archiving..."
ARCHIVE_LOG=$(mktemp)
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Automatic \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  2>&1 | tee "$ARCHIVE_LOG" | grep -E "^(Build|error:|warning: |✓|▶)" || true
if ! grep -q "ARCHIVE SUCCEEDED\|BUILD SUCCEEDED" "$ARCHIVE_LOG"; then
  echo "❌  Archive failed. Full log: $ARCHIVE_LOG"; exit 1
fi

echo "   Archive: $ARCHIVE_PATH"

# ── 2. Export (Developer ID) ──────────────────────────────────────
echo ""
echo "▶ 2/6  Exporting with Developer ID signing..."
EXPORT_LOG=$(mktemp)
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "scripts/ExportOptions.plist" \
  2>&1 | tee "$EXPORT_LOG" | grep -E "^(error:|warning: |✓)" || true
if [[ ! -d "$APP_PATH" ]]; then
  echo "❌  Export failed — $APP_PATH not found. Full log: $EXPORT_LOG"; exit 1
fi

echo "   App: $APP_PATH ($(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString) build $(defaults read "$APP_PATH/Contents/Info" CFBundleVersion))"

# ── 3. Create DMG ─────────────────────────────────────────────────
echo ""
echo "▶ 3/6  Creating DMG..."
rm -f "$DMG_PATH"

if ! command -v create-dmg &>/dev/null; then
  echo "❌  create-dmg not found. Run: brew install create-dmg"
  exit 1
fi

DMG_BG="scripts/dmg-background.png"
if [[ ! -f "$DMG_BG" ]]; then
  echo "   Generating DMG background image..."
  swift scripts/make-dmg-bg.swift "$DMG_BG"
fi

create-dmg \
  --volname "Slapppy $APP_VERSION" \
  --background "$DMG_BG" \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "Slappy.app" 165 185 \
  --app-drop-link 495 185 \
  --hide-extension "Slappy.app" \
  "$DMG_PATH" \
  "$APP_PATH"

echo "   DMG: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── 4. Notarise ───────────────────────────────────────────────────
echo ""
echo "▶ 4/6  Notarising (this takes 1–5 minutes)..."
xcrun notarytool submit "$DMG_PATH" \
  --apple-id  "$APPLE_ID" \
  --password  "$APP_PASSWORD" \
  --team-id   "$TEAM_ID" \
  --wait \
  --verbose 2>&1 | grep -E "(status:|message:|id:)" || true

# ── 5. Staple ─────────────────────────────────────────────────────
echo ""
echo "▶ 5/6  Stapling notarisation ticket..."
xcrun stapler staple "$DMG_PATH"

# ── 6. Update appcast.xml ─────────────────────────────────────────
echo ""
echo "▶ 6/6  Updating appcast.xml..."

DMG_SIZE=$(stat -f%z "$DMG_PATH")
ED_SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Slapppy</title>
    <link>https://slapppy.com/appcast.xml</link>
    <description>Slapppy release notes</description>
    <language>en</language>
    <item>
      <title>Version $APP_VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$APP_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_BASE_URL/$DMG_NAME"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$DMG_SIZE"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

echo "   Appcast: $APPCAST_PATH"

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "✅  Done!"
echo "   File: $DMG_PATH"
echo ""
echo "   Next steps:"
echo "   1. Upload $DMG_PATH to GitHub Releases (tag: v$APP_VERSION)"
echo "   2. git add docs/appcast.xml && git commit -m 'release $APP_VERSION' && git push"
echo "   3. Update Polar product file if needed"
echo ""
