#!/bin/bash

# code_sign.sh - Code sign Cameraman with project entitlements
#
# Usage:
#   ./scripts/code_sign.sh                                 # auto-detect debug binary
#   APP_PATH=/path/to/Cameraman ./scripts/code_sign.sh     # explicit path

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$REPO_ROOT/CameramanApp/CameramanApp.entitlements"
APP_PATH="${APP_PATH:-$REPO_ROOT/App/.build/arm64-apple-macosx/debug/Cameraman}"

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "❌ Entitlements file not found at $ENTITLEMENTS"
    exit 1
fi

if [[ ! -e "$APP_PATH" ]]; then
    echo "❌ Binary not found at $APP_PATH"
    echo "   Build first with: swift build (in App/) or set APP_PATH=<path>"
    exit 1
fi

echo "🔐 Signing $APP_PATH"
echo "   Entitlements: $ENTITLEMENTS"

codesign --remove-signature "$APP_PATH" 2>/dev/null || true

codesign --entitlements "$ENTITLEMENTS" \
    --force \
    --sign - \
    --timestamp \
    --options=runtime \
    "$APP_PATH"

echo "✅ Signed successfully."
echo "   Run: $APP_PATH"
