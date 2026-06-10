#!/usr/bin/env bash
# install.sh — set up claude-profiles on macOS
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_TARGET="${HOME}/.local/bin"
PYTHON="${PYTHON:-python3}"

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
die()  { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

echo -e "${BOLD}Claude Profiles — installer${RESET}"
echo

# ── Python ────────────────────────────────────────────────────────────────────
if ! command -v "$PYTHON" &>/dev/null; then
    die "Python 3 not found. Install it from https://python.org or via Homebrew."
fi

PY_VERSION="$("$PYTHON" -c 'import sys; print(sys.version_info[:2])')"
echo "Using Python: $("$PYTHON" --version)  ($PY_VERSION)"

# ── pip install (editable) ────────────────────────────────────────────────────
echo
echo "Installing claude_profiles package …"
"$PYTHON" -m pip install --quiet --editable "$REPO"
ok "Package installed"

# ── CLI symlink ───────────────────────────────────────────────────────────────
mkdir -p "$BIN_TARGET"
ln -sf "$REPO/bin/claude-profiles" "$BIN_TARGET/claude-profiles"
ok "Symlink: $BIN_TARGET/claude-profiles"

# ── PATH check ───────────────────────────────────────────────────────────────
if ! echo "$PATH" | grep -q "$BIN_TARGET"; then
    warn "$BIN_TARGET is not in your PATH."
    echo
    echo "  Add this to ~/.zshrc (or ~/.bash_profile):"
    echo "    export PATH=\"$BIN_TARGET:\$PATH\""
    echo
fi

# ── Claude Desktop check ──────────────────────────────────────────────────────
if [ ! -d "/Applications/Claude.app" ]; then
    warn "Claude Desktop not found at /Applications/Claude.app"
    warn "Download from https://claude.ai/download (needed for Desktop profiles)"
else
    CLAUDE_VER=$(defaults read /Applications/Claude.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown")
    ok "Claude Desktop found (v${CLAUDE_VER})"
fi

# ── Claude Code check ─────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    warn "claude CLI not found — Code profiles will not work until it is installed."
    warn "Install: npm install -g @anthropic-ai/claude-code"
else
    ok "Claude Code found: $(command -v claude)"
fi

echo
ok "Installation complete!"
echo
echo "Quick start:"
echo "  claude-profiles create work     --emoji 💼 --color blue"
echo "  claude-profiles create personal --emoji 🏠 --color green"
echo "  claude-profiles setup work      # create the isolated Desktop app"
echo "  claude-profiles launch work     # open Claude Desktop (work)"
echo "  claude-profiles code   personal # open Claude Code (personal)"
echo "  claude-profiles open            # GUI picker"
echo
echo "Optional: build the menu bar app"
echo "  cd MenuBarApp && swift build -c release"
echo "  # then run .build/release/ClaudeProfiles"
