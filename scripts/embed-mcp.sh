#!/bin/sh
# Build the cameraman-mcp SwiftPM executable and embed it in the app bundle at
# Contents/Helpers/, signed with the app's identity. Run as an Xcode build phase
# on the CameramanApp target (after Resources). Requires
# ENABLE_USER_SCRIPT_SANDBOXING = NO so swift build can run and write the binary.
set -eu

MCP_DIR="$SRCROOT/../MCPServer"
HELPERS_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
DEST="$HELPERS_DIR/cameraman-mcp"

if [ ! -d "$MCP_DIR" ]; then
    echo "warning: MCPServer not found at $MCP_DIR — skipping MCP embed"
    exit 0
fi

# Release ships a universal helper (the app itself is arm64 + x86_64); Debug builds native only.
ARCH_FLAGS=""
if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "Building cameraman-mcp (release${ARCH_FLAGS:+, universal})…"
# shellcheck disable=SC2086
xcrun swift build -c release $ARCH_FLAGS --package-path "$MCP_DIR" --product cameraman-mcp

# shellcheck disable=SC2086
BUILT="$(xcrun swift build -c release $ARCH_FLAGS --package-path "$MCP_DIR" --product cameraman-mcp --show-bin-path)/cameraman-mcp"
if [ ! -f "$BUILT" ]; then
    echo "error: built MCP binary not found at $BUILT"
    exit 1
fi

if [ -n "$ARCH_FLAGS" ]; then
    ARCHS_FOUND="$(lipo -archs "$BUILT")"
    case "$ARCHS_FOUND" in
        *arm64*x86_64*|*x86_64*arm64*) ;;
        *) echo "error: Release helper is not universal ($ARCHS_FOUND)"; exit 1 ;;
    esac
fi

mkdir -p "$HELPERS_DIR"
cp -f "$BUILT" "$DEST"

# Nested executables must be signed individually (hardened runtime; the outer app signature then
# seals this). A real identity needs a secure timestamp or notarization rejects the helper; the
# ad-hoc identity ("-", Debug) cannot take one and must skip it.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --options runtime --timestamp=none --sign - "$DEST"
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$DEST"
fi
echo "Embedded MCP server at $DEST"
