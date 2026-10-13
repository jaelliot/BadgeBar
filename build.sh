#!/bin/bash
# Builds BadgeBar.app from the Swift package and ad-hoc code-signs it.
# No Xcode required — only the Swift toolchain from Command Line Tools.
set -euo pipefail

APP_NAME="BadgeBar"
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-release}"
BIN_DIR="$ROOT/.build/$CONFIG"
APP_DIR="$ROOT/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$ROOT/AppIcon.icns" ]; then
    cp "$ROOT/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# Do not unlock keychains with hard-coded passwords or automatically create
# signing identities. For distribution, supply a trusted signing identity.
# Local builds use ad-hoc signatures and may require new Accessibility consent.
if [ -n "${BADGEBAR_SIGNING_IDENTITY:-}" ]; then
    codesign --force --options runtime --sign "$BADGEBAR_SIGNING_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
fi
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "✓ Built $APP_DIR"
