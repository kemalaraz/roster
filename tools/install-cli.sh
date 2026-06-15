#!/bin/bash
# Install Roster's terminal shims: typing `claude` (and `codex`, if installed) shows
# the profile picker. Idempotent. Run:  bash tools/install-cli.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HOME/.roster/bin"
mkdir -p "$BIN"

install_one() {
  local tool="$1"
  cp "$ROOT/tools/roster-shim.sh" "$BIN/$tool"
  chmod +x "$BIN/$tool"
  echo "  ✓ $BIN/$tool"
}

echo "→ Installing shims…"
install_one claude
if command -v codex >/dev/null 2>&1; then install_one codex; else echo "  • codex not on PATH — skipping (re-run after installing it)"; fi

# Add ~/.roster/bin to PATH (zsh + bash), idempotent + clearly marked.
add_path() {
  local rc="$1"; [ -e "$rc" ] || return 0
  grep -q 'roster/bin' "$rc" 2>/dev/null && return 0
  printf '\n# >>> Roster CLI shims >>>\nexport PATH="$HOME/.roster/bin:$PATH"\n# <<< Roster CLI shims <<<\n' >> "$rc"
  echo "  ✓ added PATH line to $rc"
}
echo "→ Updating shell PATH…"
add_path "$HOME/.zshrc"
[ -e "$HOME/.bashrc" ] && add_path "$HOME/.bashrc" || true

echo "✓ Done. Open a new terminal (or 'source ~/.zshrc'), then type 'claude'."
