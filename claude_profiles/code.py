"""Claude Code profile isolation.

Claude Code reads its config from ~/.claude/ by default.  It honours the
CLAUDE_CONFIG_DIR environment variable, which lets us point each profile at
its own directory without touching the real ~/.claude/.

If the env-var approach does not work with a given Claude Code build, we also
provide wrapper scripts (one per profile) placed in ~/.claude-profiles/bin/.
Add that directory to PATH and you can type `claude-work`, `claude-personal`,
etc., just like a normal `claude` invocation.
"""
from __future__ import annotations
import os
import shutil
import subprocess
from pathlib import Path
from typing import Optional

from .profile import Profile, PROFILES_DIR

_BIN_DIR = PROFILES_DIR / "bin"
_CLAUDE_BIN = shutil.which("claude") or "/usr/local/bin/claude"


class CodeManager:
    def __init__(self):
        _BIN_DIR.mkdir(parents=True, exist_ok=True)

    # ──────────────────────────────────────────────────────────────
    # public API
    # ──────────────────────────────────────────────────────────────

    def setup(self, profile: Profile) -> Path:
        """Ensure config dir exists and create a named wrapper script."""
        profile.code_config_dir.mkdir(parents=True, exist_ok=True)
        return self._write_wrapper(profile)

    def launch(self, profile: Profile, extra_args: list[str] | None = None) -> None:
        """Run claude with the profile's config dir via CLAUDE_CONFIG_DIR."""
        env = {**os.environ, "CLAUDE_CONFIG_DIR": str(profile.code_config_dir)}
        cmd = [_CLAUDE_BIN, *(extra_args or [])]
        # Replace current process — lets the terminal handle I/O normally.
        os.execvpe(cmd[0], cmd, env)

    def wrapper_path(self, profile: Profile) -> Path:
        return _BIN_DIR / f"claude-{profile.slug}"

    def bin_dir(self) -> Path:
        return _BIN_DIR

    # ──────────────────────────────────────────────────────────────
    # internals
    # ──────────────────────────────────────────────────────────────

    def _write_wrapper(self, profile: Profile) -> Path:
        path = self.wrapper_path(profile)
        path.write_text(
            f"""#!/usr/bin/env bash
# Claude Code wrapper — profile: {profile.display_name}
exec env CLAUDE_CONFIG_DIR="{profile.code_config_dir}" {_CLAUDE_BIN} "$@"
"""
        )
        path.chmod(0o755)
        return path
