"""Manages per-profile Claude Desktop app bundles.

Strategy: copy /Applications/Claude.app → ~/Applications/Claude-{slug}.app,
then patch CFBundleIdentifier in Info.plist.  macOS creates a fully isolated
sandbox (Keychain + Application Support) per bundle ID, so each profile gets
its own login session.
"""
from __future__ import annotations
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

from .profile import Profile, CLAUDE_APP_SOURCE, USER_APPS_DIR


def _run(cmd: list[str], check=False) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


class DesktopManager:
    def __init__(self, source: Path = CLAUDE_APP_SOURCE):
        self.source = source
        USER_APPS_DIR.mkdir(exist_ok=True)

    # ──────────────────────────────────────────────────────────────
    # public API
    # ──────────────────────────────────────────────────────────────

    def setup(self, profile: Profile, force: bool = False) -> Path:
        """Create or refresh the profile's app bundle from the source app."""
        if not self.source.exists():
            raise FileNotFoundError(
                f"Claude Desktop not found at {self.source}\n"
                "Download it from https://claude.ai/download"
            )

        dest = profile.app_path
        if dest.exists():
            if not force:
                # Just re-patch — preserves any manual tweaks
                self._patch_plist(dest, profile)
                self._strip_signature(dest)
                return dest
            shutil.rmtree(dest)

        print(f"  Copying {self.source.name} → {dest.name} …", flush=True)
        shutil.copytree(str(self.source), str(dest), symlinks=True)
        self._patch_plist(dest, profile)
        self._strip_signature(dest)
        self._remove_quarantine(dest)
        return dest

    def launch(self, profile: Profile) -> None:
        if not profile.app_path.exists():
            print(f"App bundle not found — setting up for '{profile.display_name}' …")
            self.setup(profile)
        subprocess.Popen(
            ["open", str(profile.app_path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def sync_all(self, profiles: list[Profile]) -> None:
        """Re-copy from source after a Claude Desktop update."""
        for p in profiles:
            if p.app_path.exists():
                print(f"  Syncing '{p.display_name}' …")
                self.setup(p, force=True)
                print(f"  ✓ {p.app_name}")

    def source_version(self) -> Optional[str]:
        plist_path = self.source / "Contents" / "Info.plist"
        if not plist_path.exists():
            return None
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)
        return plist.get("CFBundleShortVersionString")

    def is_running(self, profile: Profile) -> bool:
        r = _run(["pgrep", "-f", profile.bundle_id])
        return r.returncode == 0

    # ──────────────────────────────────────────────────────────────
    # internals
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    def _patch_plist(app: Path, profile: Profile) -> None:
        plist_path = app / "Contents" / "Info.plist"
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)

        plist["CFBundleIdentifier"]  = profile.bundle_id
        plist["CFBundleName"]        = profile.app_name
        plist["CFBundleDisplayName"] = profile.app_name

        with open(plist_path, "wb") as f:
            plistlib.dump(plist, f)

    @staticmethod
    def _strip_signature(app: Path) -> None:
        # Signature is invalid after plist edit; remove it so macOS doesn't reject the app.
        _run(["codesign", "--remove-signature", str(app)])

    @staticmethod
    def _remove_quarantine(app: Path) -> None:
        _run(["xattr", "-cr", str(app)])
