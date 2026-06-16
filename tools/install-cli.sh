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
# `roster` launcher → the app binary (so `roster doctor` etc. work from the terminal).
printf '#!/bin/bash\nexec "/Applications/Roster.app/Contents/MacOS/Roster" "$@"\n' > "$BIN/roster"
chmod +x "$BIN/roster"; echo "  ✓ $BIN/roster"

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

echo ""
echo "  ┌────────────────────────────────────────────────┐"
echo "  │  IMPORTANT: open a NEW terminal window/tab now.  │"
echo "  │  (Existing terminals won't see the picker until  │"
echo "  │   you do — or run:  exec zsh)                    │"
echo "  └────────────────────────────────────────────────┘"
echo ""
echo "✓ Done. In a new terminal, type 'claude' to pick a profile, or 'roster doctor' to check setup."
