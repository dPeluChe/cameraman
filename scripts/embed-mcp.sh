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

echo "Building cameraman-mcp (release)…"
xcrun swift build -c release --package-path "$MCP_DIR" --product cameraman-mcp

BUILT="$(xcrun swift build -c release --package-path "$MCP_DIR" --product cameraman-mcp --show-bin-path)/cameraman-mcp"
if [ ! -f "$BUILT" ]; then
    echo "error: built MCP binary not found at $BUILT"
    exit 1
fi

mkdir -p "$HELPERS_DIR"
cp -f "$BUILT" "$DEST"

# Nested executables must be individually signed (hardened runtime for release;
# the outer app signature then seals this). Ad-hoc identity ("-") for Debug.
codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$DEST"
echo "Embedded MCP server at $DEST"
