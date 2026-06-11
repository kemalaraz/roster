#!/bin/bash
# Build the standalone Claude Profiles.app — native Objective-C / Cocoa, no
# external dependencies (no Python, no conda, no Swift runtime). Requires only
# the Xcode Command Line Tools (clang).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
BUILD="$ROOT/build"
APP="$BUILD/Claude Profiles.app"
BIN="ClaudeProfiles"

echo "→ Cleaning…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Compiling (clang, ARC, Cocoa)…"
clang -fobjc-arc -fmodules -framework Cocoa \
    -mmacosx-version-min=13.0 \
    -Wall -O2 \
    -I "$APP_DIR/src" \
    -o "$APP/Contents/MacOS/$BIN" \
    "$APP_DIR"/src/*.m

echo "→ Assembling bundle…"
cp "$APP_DIR/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/resources/icon.icns" ]; then
    cp "$ROOT/resources/icon.icns" "$APP/Contents/Resources/icon.icns"
fi

echo "→ Ad-hoc signing…"
codesign --sign - --force --deep "$APP" >/dev/null 2>&1 || true

echo "✓ Built: $APP"
