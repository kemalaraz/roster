#!/usr/bin/env bash
set -euo pipefail

BOLD="\033[1m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; RESET="\033[0m"
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }

echo -e "${BOLD}Claude Profiles — uninstaller${RESET}"
echo
read -r -p "Remove the claude-profiles CLI and all profile app bundles? [y/N] " ans
[[ "${ans,,}" != "y" ]] && { echo "Aborted."; exit 0; }

# Remove symlink
rm -f "${HOME}/.local/bin/claude-profiles"
ok "Removed CLI symlink"

# Remove profile app bundles from ~/Applications/
for app in "${HOME}/Applications"/Claude-*.app; do
    [ -d "$app" ] && rm -rf "$app" && ok "Removed $app"
done

# Remove wrapper scripts
[ -d "${HOME}/.claude-profiles/bin" ] && rm -rf "${HOME}/.claude-profiles/bin"
ok "Removed wrapper scripts"

# Pip uninstall
python3 -m pip uninstall -y claude-profiles 2>/dev/null && ok "pip package removed" || true

echo
warn "Profile config data at ~/.claude-profiles/ was NOT removed."
warn "Delete it manually if you want to wipe login sessions:"
warn "  rm -rf ~/.claude-profiles"
echo
ok "Uninstall complete."
