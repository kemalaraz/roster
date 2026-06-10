#!/usr/bin/env bash
# build-app.sh — produces dist/Claude Profiles.app (self-contained, no install needed)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Claude Profiles"
BUNDLE="$REPO/dist/${APP_NAME}.app"
CONTENTS="$BUNDLE/Contents"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "  $*"; }

echo -e "${BOLD}Building ${APP_NAME}.app …${RESET}"
echo

# ── Pre-flight ────────────────────────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
    echo "Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Python 3 not found."
    exit 1
fi

# ── Build Swift binary ────────────────────────────────────────────────────────
info "Compiling Swift menu bar app …"
cd "$REPO/MenuBarApp"
swift build -c release 2>&1 | grep -v "^Build complete" | grep -v "^warning:" || true
cd "$REPO"
ok "Swift build complete"

# ── Assemble .app bundle ──────────────────────────────────────────────────────
info "Assembling bundle …"
rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources/bin"
mkdir -p "$CONTENTS/Resources/claude_profiles"

# Executable
cp "$REPO/MenuBarApp/.build/release/ClaudeProfiles" "$CONTENTS/MacOS/ClaudeProfiles"

# Info.plist
cp "$REPO/MenuBarApp/Resources/Info.plist" "$CONTENTS/Info.plist"

# Bundle the Python package so the app is self-contained
cp -r "$REPO/claude_profiles/"     "$CONTENTS/Resources/claude_profiles/"
cp    "$REPO/bin/claude-profiles"  "$CONTENTS/Resources/bin/claude-profiles"
chmod +x "$CONTENTS/Resources/bin/claude-profiles"

ok "Bundle assembled: $BUNDLE"

# ── Remove quarantine ─────────────────────────────────────────────────────────
xattr -cr "$BUNDLE" 2>/dev/null || true

echo
echo -e "${BOLD}Done!${RESET}"
echo
echo "  Drag to /Applications:    cp -r \"$BUNDLE\" /Applications/"
echo "  Or open directly:         open \"$BUNDLE\""
echo
echo "First launch on a new Mac: right-click → Open to bypass Gatekeeper."
