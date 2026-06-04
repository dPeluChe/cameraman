#!/usr/bin/env bash
set -euo pipefail

# notarize-dmg.sh — submit a DMG to Apple notary service and staple the ticket.
#
# One-time setup (stores the app-specific password in your keychain so you
# never type it again):
#
#   xcrun notarytool store-credentials cameraman-notary \
#       --apple-id antonio@feedby.ai \
#       --team-id NQHHJ85736 \
#       --password <app-specific-password>   # from appleid.apple.com
#
# Usage:
#   ./scripts/notarize-dmg.sh dist/Cameraman-beta-0.6.1.8.dmg
#   PROFILE=other-profile ./scripts/notarize-dmg.sh path/to.dmg

PROFILE="${PROFILE:-cameraman-notary}"
DMG="${1:-}"

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "❌ Pass the DMG path: ./scripts/notarize-dmg.sh <file.dmg>" >&2
  exit 1
fi

echo "📤 Submitting $DMG to Apple notary (profile: $PROFILE)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "📎 Stapling ticket…"
xcrun stapler staple "$DMG"

echo "🔎 Validating…"
xcrun stapler validate "$DMG"
spctl -a -vvv -t install "$DMG" 2>&1 | grep -E "accepted|source" || true

echo "✅ Done — $DMG is notarized and stapled."
