#!/bin/bash

# code_sign.sh - Code sign Cameraman with ScreenCaptureKit entitlements

set -e

APP_PATH="/Users/peluche/dPeluCheData/PROJECTS/dPeluChe/_code_/labs-cameraman/App/.build/arm64-apple-macosx/debug/Cameraman"

echo "🔐 Firmando Cameraman con entitlements para ScreenCaptureKit..."

# Create entitlements file with sandbox and ScreenCaptureKit access
cat > /tmp/Cameraman.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

# Remove existing signature
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# Sign with entitlements
codesign --entitlements /tmp/Cameraman.entitlements \
    --force \
    --sign - \
    --timestamp \
    --options=runtime \
    "$APP_PATH"

echo "✅ Cameraman firmado correctamente."
echo ""
echo "ℹ️  Ahora ejecuta la app desde Xcode o directamente desde:"
echo "   $APP_PATH"
