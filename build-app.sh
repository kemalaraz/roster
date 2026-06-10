#!/usr/bin/env bash
# build-app.sh — produces dist/Claude Profiles.app
#
# Default: Python-based menu bar (works with Xcode Command Line Tools only).
# Pass --swift to build the native Swift version (requires full Xcode).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Claude Profiles"
BUNDLE="$REPO/dist/${APP_NAME}.app"
CONTENTS="$BUNDLE/Contents"
USE_SWIFT=false

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
info() { echo -e "  $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
die()  { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

for arg in "$@"; do [[ "$arg" == "--swift" ]] && USE_SWIFT=true; done

echo -e "${BOLD}Building ${APP_NAME}.app …${RESET}"

# ── Pre-flight ────────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    die "python3 not found."
fi

PYTHON=$(python3 -c "import sys; print(sys.executable)")

# Prefer the conda claude-profiles env if it exists
CONDA_PYTHON="$HOME/miniconda3/envs/claude-profiles/bin/python3"
[[ -f "$CONDA_PYTHON" ]] && PYTHON="$CONDA_PYTHON"

info "Python: $PYTHON"

if ! "$PYTHON" -c "import rumps" 2>/dev/null; then
    warn "'rumps' not found in $PYTHON — installing …"
    "$PYTHON" -m pip install --quiet rumps
fi
ok "rumps available"

# ── Assemble .app bundle ──────────────────────────────────────────────────────
if $USE_SWIFT; then
    # ── Swift build (requires full Xcode) ──────────────────────
    if ! command -v swift &>/dev/null; then
        die "Swift not found. Install Xcode from the App Store."
    fi

    # Check for the SwiftBridging CLT bug (CLT without full Xcode)
    if ! swift -e "import Cocoa" 2>/dev/null | grep -q "ok"; then
        if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
            die "The Xcode Command Line Tools have a Swift module conflict that prevents GUI builds.
Install full Xcode from the App Store (free), then re-run:
  sudo xcode-select -s /Applications/Xcode.app
  make app --swift"
        fi
    fi

    info "Compiling Swift menu bar app …"
    cd "$REPO/MenuBarApp"
    if ! swift build -c release 2>&1; then
        die "Swift build failed — see errors above."
    fi
    BINARY=".build/release/ClaudeProfiles"
    [[ -f "$BINARY" ]] || die "Binary not found at MenuBarApp/$BINARY after build."
    cd "$REPO"
    ok "Swift build complete"

    rm -rf "$BUNDLE"
    mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/bin" "$CONTENTS/Resources/claude_profiles"
    cp "$REPO/MenuBarApp/.build/release/ClaudeProfiles" "$CONTENTS/MacOS/ClaudeProfiles"
    cp "$REPO/MenuBarApp/Resources/Info.plist"          "$CONTENTS/Info.plist"
    cp -r "$REPO/claude_profiles/"    "$CONTENTS/Resources/claude_profiles/"
    cp    "$REPO/bin/claude-profiles" "$CONTENTS/Resources/bin/claude-profiles"
    chmod +x "$CONTENTS/Resources/bin/claude-profiles"
    info "Backend: Swift"
else
    # ── Python build (default — no Xcode required) ──────────────
    rm -rf "$BUNDLE"
    mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/bin" "$CONTENTS/Resources/claude_profiles"

    # Launcher shell script that invokes the bundled Python
    cat > "$CONTENTS/MacOS/ClaudeProfiles" << LAUNCHER
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RESOURCES="\$DIR/../Resources"
exec "$PYTHON" "\$RESOURCES/menubar/menubar.py"
LAUNCHER
    chmod +x "$CONTENTS/MacOS/ClaudeProfiles"

    # Info.plist
    cp "$REPO/MenuBarApp/Resources/Info.plist" "$CONTENTS/Info.plist"

    # Bundle Python files
    cp -r "$REPO/menubar/"            "$CONTENTS/Resources/menubar/"
    cp -r "$REPO/claude_profiles/"    "$CONTENTS/Resources/claude_profiles/"
    cp    "$REPO/bin/claude-profiles" "$CONTENTS/Resources/bin/claude-profiles"
    chmod +x "$CONTENTS/Resources/bin/claude-profiles"
    info "Backend: Python (rumps)"
fi

# ── Remove quarantine ─────────────────────────────────────────────────────────
xattr -cr "$BUNDLE" 2>/dev/null || true
ok "Bundle assembled"

echo
echo -e "${BOLD}Done!${RESET}  →  $BUNDLE"
echo
echo "  Install:  cp -r \"$BUNDLE\" /Applications/"
echo "  Or run:   open \"$BUNDLE\""
echo
echo "First launch: right-click → Open to bypass Gatekeeper (unsigned app)."
