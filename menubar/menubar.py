#!/usr/bin/env python3
"""Claude Profiles — menu bar app.

Requires: pip install rumps   (or: conda install -c conda-forge rumps)
"""
from __future__ import annotations
import json
import os
import plistlib
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional

import rumps
from Foundation import NSOperationQueue  # part of pyobjc, ships with rumps

# ── Paths ──────────────────────────────────────────────────────────────────────

PROFILES_JSON = Path.home() / ".claude-profiles" / "profiles.json"
VERSION_JSON  = Path.home() / ".claude-profiles" / "claude-version.json"
CLAUDE_APP    = Path("/Applications/Claude.app")
CLAUDE_PLIST  = CLAUDE_APP / "Contents" / "Info.plist"


def _find_cli() -> str:
    """Locate the claude-profiles CLI, preferring the bundled copy inside .app."""
    # When running from inside a .app bundle the Resources/ dir is two levels up
    bundled = Path(sys.executable).parent.parent / "Resources" / "bin" / "claude-profiles"
    if bundled.exists():
        return str(bundled)
    for p in [
        Path.home() / ".local/bin/claude-profiles",
        Path("/opt/homebrew/bin/claude-profiles"),
        Path("/usr/local/bin/claude-profiles"),
    ]:
        if p.exists():
            return str(p)
    return "claude-profiles"


# ── Data helpers ───────────────────────────────────────────────────────────────

def _load_profiles() -> list[dict]:
    if not PROFILES_JSON.exists():
        return []
    try:
        return json.loads(PROFILES_JSON.read_text()).get("profiles", [])
    except Exception:
        return []


def _installed_version() -> Optional[str]:
    if not CLAUDE_PLIST.exists():
        return None
    try:
        with open(CLAUDE_PLIST, "rb") as f:
            return plistlib.load(f).get("CFBundleShortVersionString")
    except Exception:
        return None


def _synced_version() -> Optional[str]:
    if not VERSION_JSON.exists():
        return None
    try:
        return json.loads(VERSION_JSON.read_text()).get("synced_version")
    except Exception:
        return None


def _update_pending() -> Optional[tuple[str, str]]:
    """Return (synced, installed) if versions differ, else None."""
    installed = _installed_version()
    synced    = _synced_version()
    if installed and synced and installed != synced:
        return (synced, installed)
    return None


def _open_terminal(cmd: str) -> None:
    ghostty = Path("/Applications/Ghostty.app")
    if ghostty.exists():
        subprocess.Popen(
            [str(ghostty / "Contents/MacOS/ghostty"), f"--command=bash -lc '{cmd}; exec bash'"],
        )
    else:
        safe = cmd.replace('"', '\\"')
        script = (
            f'tell application "Terminal" to activate\n'
            f'tell application "Terminal" to do script "{safe}"'
        )
        subprocess.run(["osascript", "-e", script])


# ── App ────────────────────────────────────────────────────────────────────────

class ClaudeProfilesApp(rumps.App):

    ICON_IDLE   = "◉ Profiles"
    ICON_SYNC   = "⟳ "
    ICON_ALERT  = "👤⚠️"

    def __init__(self):
        super().__init__("Claude Profiles", title=self.ICON_IDLE, quit_button=None)
        self._cli     = _find_cli()
        self._syncing = False
        self._rebuild_menu()
        # Periodic update check — every 30 minutes
        self._check_timer = rumps.Timer(self._periodic_check, 30 * 60)
        self._check_timer.start()
        # Check on launch
        self._check_for_update(notify=False)

    # ── Menu construction ──────────────────────────────────────────────────────

    def _rebuild_menu(self) -> None:
        profiles = _load_profiles()
        pending  = _update_pending()
        items: list = []

        # ── Profiles ──────────────────────────────────────────────
        if not profiles:
            empty = rumps.MenuItem("No profiles yet — click New Profile…")
            empty.set_callback(None)
            items.append(empty)
        else:
            for p in profiles:
                name    = p["name"]
                label   = f"{p.get('emoji', '👤')}  {p.get('display_name', name)}"
                parent  = rumps.MenuItem(label)
                installed_ok = (
                    Path.home() / "Applications" / f"Claude-{name}.app"
                ).exists()

                parent["Launch Desktop"] = rumps.MenuItem(
                    "Launch Desktop" if installed_ok else "Launch Desktop (setup required)",
                    callback=lambda _, n=name: self._launch_desktop(n),
                )
                parent["Open Claude Code"] = rumps.MenuItem(
                    "Open Claude Code",
                    callback=lambda _, n=name: _open_terminal(f"claude-profiles code {n}"),
                )
                parent[None] = None
                parent["Setup Desktop Bundle"] = rumps.MenuItem(
                    "Setup Desktop Bundle",
                    callback=lambda _, n=name: _open_terminal(
                        f"claude-profiles setup {n} && echo '✓ Done'"
                    ),
                )
                items.append(parent)

        items.append(None)

        # ── Update badge ───────────────────────────────────────────
        if pending:
            synced, installed = pending
            badge = rumps.MenuItem(
                f"⚠️  Claude v{synced} → v{installed} — Click to sync",
                callback=self._sync_clicked,
            )
            items.append(badge)
            items.append(None)

        # ── Actions ────────────────────────────────────────────────
        items.append(rumps.MenuItem("New Profile…", callback=self._new_profile))
        items.append(None)
        items.append(rumps.MenuItem(
            "Syncing…" if self._syncing else "Sync Profiles",
            callback=None if self._syncing else self._sync_clicked,
        ))
        items.append(rumps.MenuItem("Refresh", callback=self._refresh))
        items.append(None)
        items.append(rumps.MenuItem("Quit", callback=rumps.quit_application))

        self.menu.clear()
        self.menu.update(items)

    # ── Menu actions ───────────────────────────────────────────────────────────

    def _launch_desktop(self, name: str) -> None:
        subprocess.Popen(
            [self._cli, "launch", name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _new_profile(self, _) -> None:
        # Uses the existing AppleScript GUI picker from cli.py
        subprocess.Popen([self._cli, "open"])

    def _sync_clicked(self, _) -> None:
        if self._syncing:
            return
        installed = _installed_version()
        if not installed:
            return
        self._run_sync(installed)

    def _refresh(self, _) -> None:
        self._check_for_update(notify=False)
        self._rebuild_menu()

    def _periodic_check(self, _timer) -> None:
        self._check_for_update(notify=True)

    # ── Sync ───────────────────────────────────────────────────────────────────

    def _run_sync(self, new_version: str) -> None:
        self._syncing = True
        self.title = self.ICON_SYNC
        self._rebuild_menu()

        def _worker():
            result = subprocess.run(
                [self._cli, "sync"],
                capture_output=True,
                text=True,
            )
            success = result.returncode == 0
            # schedule UI update back on main thread via NSOperationQueue
            NSOperationQueue.mainQueue().addOperationWithBlock_(
                lambda: self._sync_finished(success, new_version)
            )

        threading.Thread(target=_worker, daemon=True).start()

    def _sync_finished(self, success: bool, new_version: str) -> None:
        self._syncing = False
        self.title = self.ICON_IDLE
        self._rebuild_menu()
        if success:
            rumps.notification(
                "Claude Profiles",
                "Sync Complete",
                f"All profiles updated to Claude v{new_version}.",
            )
        else:
            rumps.notification(
                "Claude Profiles",
                "Sync Failed",
                "Run 'claude-profiles sync' in Terminal for details.",
            )

    # ── Update detection ───────────────────────────────────────────────────────

    def _check_for_update(self, notify: bool = True) -> None:
        pending = _update_pending()
        if pending:
            synced, installed = pending
            self.title = self.ICON_ALERT
            self._rebuild_menu()
            if notify:
                rumps.notification(
                    "Claude Desktop Updated",
                    f"v{synced} → v{installed}",
                    "Open the menu bar to sync your profiles.",
                    sound=False,
                )
        else:
            if self.title == self.ICON_ALERT:
                self.title = self.ICON_IDLE
            self._rebuild_menu()


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ClaudeProfilesApp().run()
