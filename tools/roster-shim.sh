#!/bin/bash
# Roster CLI shim. Installed (as `claude` and/or `codex`) on PATH ahead of the real
# binary. Typing the command interactively shows Roster's profile picker, then execs
# the real binary with the right per-profile config dir + a titled window. The tool is
# taken from this script's own name ($0), so the same file works for claude and codex.
#
# Bypass:  <tool> --profile <name>   (or -P <name>)   — works non-interactively too
# Skips entirely when non-interactive or when the config env var is already set.
ROSTER="/Applications/Roster.app/Contents/MacOS/Roster"
TOOL="$(basename "$0")"
case "$TOOL" in
  claude) ENVVAR="CLAUDE_CONFIG_DIR"; SUBDIR="claude-code"; LABEL="Claude Code";;
  codex)  ENVVAR="CODEX_HOME";        SUBDIR="codex";       LABEL="Codex";;
  *) echo "roster shim: unknown tool '$TOOL'" >&2; exit 2;;
esac

# Resolve the real binary (PATH without our shim dir) to avoid recursing into the shim.
REAL="$(PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "$HOME/.roster/bin" | paste -sd: -)" command -v "$TOOL" 2>/dev/null)"
[ -z "$REAL" ] && { echo "roster: real '$TOOL' not found on PATH" >&2; exit 127; }

prof=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --profile|-P) prof="${2:-}"; shift 2 2>/dev/null || shift;;
    *) args+=("$1"); shift;;
  esac
done

# Respect a config dir already chosen upstream (e.g. Roster's "Open Code").
[ -n "${!ENVVAR}" ] && exec "$REAL" "${args[@]}"

dir=""
if [ -n "$prof" ]; then                        # explicit --profile (works anywhere)
  slug="$(printf '%s' "$prof" | tr '[:upper:] _' '[:lower:]--')"
  dir="$HOME/.claude-profiles/$slug/$SUBDIR"; mkdir -p "$dir"
elif [ -t 0 ] && [ -t 1 ]; then                # interactive → styled picker
  dir="$("$ROSTER" --pick "$TOOL")"; rc=$?     # rc!=0 → cancelled (esc)
  [ "$rc" -ne 0 ] && exit 0                     # cancel → open nothing
else
  exec "$REAL" "${args[@]}"                     # non-interactive → global, no prompt
fi
[ -z "$dir" ] && exec "$REAL" "${args[@]}"      # Default → global ~/.claude

printf '\033]0;%s · %s\007' "$(basename "$(dirname "$dir")")" "$LABEL"   # title = profile
exec env "$ENVVAR=$dir" "$REAL" "${args[@]}"
