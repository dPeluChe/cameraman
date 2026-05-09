#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="CameramanApp"
VOLUME_NAME="Cameraman"
DMG_BASENAME="Cameraman-beta"

SRC_APP="$ROOT/CameramanApp/build/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="$ROOT/dist"
STAGING="$DIST_DIR/staging"
BG_SRC="$ROOT/docs/branding/dmg-background@2x.jpg"
BG_TMP="$DIST_DIR/dmg-bg.png"

if [[ ! -d "$SRC_APP" ]]; then
  echo "❌ Release build not found at: $SRC_APP" >&2
  echo "   Run: make build" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null; then
  echo "❌ create-dmg not installed. Install with: brew install create-dmg" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SRC_APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SRC_APP/Contents/Info.plist")
DMG_OUT="$DIST_DIR/${DMG_BASENAME}-${VERSION}.${BUILD}.dmg"

rm -rf "$STAGING" "$DMG_OUT"
mkdir -p "$STAGING"

# Force-unmount any leftover create-dmg volumes from previous runs (Resource-busy guard)
for vol in /Volumes/dmg.*; do
  [[ -d "$vol" ]] && hdiutil detach -force "$vol" >/dev/null 2>&1 || true
done
# Remove orphaned temporary read-write DMGs from a previous failed run
rm -f "$DIST_DIR"/rw.*.dmg

# DMG window is 660×464 @1x — preserves the 1.42:1 aspect of the source background.
sips -s format png -z 464 660 "$BG_SRC" --out "$BG_TMP" >/dev/null

cp -R "$SRC_APP" "$STAGING/"

create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$BG_TMP" \
  --window-pos 200 120 \
  --window-size 660 464 \
  --icon-size 128 \
  --icon "${APP_NAME}.app" 180 215 \
  --app-drop-link 480 215 \
  --no-internet-enable \
  "$DMG_OUT" \
  "$STAGING"

echo ""
echo "✅ DMG: $DMG_OUT"
echo "   Size: $(du -h "$DMG_OUT" | cut -f1)"
