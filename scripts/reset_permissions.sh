#!/bin/bash

# reset_permissions.sh - Reset macOS TCC permissions for Cameraman
# This clears cached permissions so macOS will prompt again

set -e

echo "🧹 Reseteando permisos TCC para Cameraman..."

# Kill the app if running
osascript -e 'tell application "Cameraman" to quit' 2>/dev/null || true
osascript -e 'tell application "cameraman" to quit' 2>/dev/null || true

# Remove cached permissions for the app
tccutil reset ScreenCapture com.apple.dt.Xcode 2>/dev/null || true

# Reset the system's screen recording permission database entry
# This forces macOS to ask for permissions again on next access
sudo rm -f /Library/Application\ Support/com.apple.TCC/TCC.db 2>/dev/null || true

# Alternative: Reset only for our bundle ID if using codesign
# Replace with your actual bundle ID
BUNDLE_ID="com.cameraman.app"
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true

echo "✅ Permisos reseteados."
echo ""
echo "ℹ️  Ahora:"
echo "   1. Abre Xcode"
echo "   2. Clean Build Folder (Cmd+Shift+K)"
echo "   3. Run (Cmd+R)"
echo "   4. Cuando pida permisos, haz clic en 'Allow'"
