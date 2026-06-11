"""Manages per-profile Claude Desktop app bundles.

Strategy: copy /Applications/Claude.app → ~/Applications/Claude-{slug}.app,
then patch CFBundleIdentifier in Info.plist.  macOS creates a fully isolated
sandbox (Keychain + Application Support) per bundle ID, so each profile gets
its own login session.
"""
from __future__ import annotations
import json
import plistlib
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .profile import Profile, CLAUDE_APP_SOURCE, USER_APPS_DIR, PROFILES_DIR

# Shared with the Swift menu bar app — both sides read/write this file.
_VERSION_FILE = PROFILES_DIR / "claude-version.json"


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
                self._patch_plist(dest, profile)
                self._strip_signature(dest)
                self._remove_quarantine(dest)
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
        self._remove_quarantine(profile.app_path)
        # Pass --user-data-dir so each profile gets its own Electron userData path.
        # Claude Desktop hardcodes the path otherwise; all profiles would share one session.
        user_data = (
            Path.home() / "Library" / "Application Support" / f"Claude-{profile.name}"
        )
        subprocess.Popen(
            ["open", "-n", str(profile.app_path), "--args", f"--user-data-dir={user_data}"],
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
        # Record synced version so the menu bar app (and next CLI run) knows we're up to date.
        version = self.source_version()
        if version:
            self.write_synced_version(version)

    def source_version(self) -> Optional[str]:
        plist_path = self.source / "Contents" / "Info.plist"
        if not plist_path.exists():
            return None
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)
        return plist.get("CFBundleShortVersionString")

    # ── Version tracking (shared with menu bar app) ───────────────

    def synced_version(self) -> Optional[str]:
        """Return the last version that was synced, or None if never synced."""
        if not _VERSION_FILE.exists():
            return None
        try:
            data = json.loads(_VERSION_FILE.read_text())
            return data.get("synced_version")
        except (json.JSONDecodeError, OSError):
            return None

    def write_synced_version(self, version: str) -> None:
        _VERSION_FILE.parent.mkdir(parents=True, exist_ok=True)
        _VERSION_FILE.write_text(json.dumps({
            "synced_version": version,
            "last_synced": datetime.now(timezone.utc).isoformat(),
        }, indent=2))

    def update_available(self) -> Optional[tuple[str, str]]:
        """Return (synced_version, installed_version) if an update is pending, else None."""
        installed = self.source_version()
        synced    = self.synced_version()
        if installed and synced and installed != synced:
            return (synced, installed)
        return None

    def is_running(self, profile: Profile) -> bool:
        r = _run(["pgrep", "-f", profile.bundle_id])
        return r.returncode == 0

    # ──────────────────────────────────────────────────────────────
    # internals
    # ──────────────────────────────────────────────────────────────

    @staticmethod
    def _patch_plist(app: Path, profile: Profile) -> None:
        # Electron derives helper paths AND userData dir from CFBundleName.
        # We must use a unique, filesystem-safe name per profile so that:
        #   - Electron finds renamed helpers: Frameworks/{internal} Helper.app
        #   - userData lands in ~/Library/Application Support/{internal}
        # CFBundleDisplayName is what the Dock/Finder actually shows.
        internal = f"Claude-{profile.name}"

        plist_path = app / "Contents" / "Info.plist"
        with open(plist_path, "rb") as f:
            plist = plistlib.load(f)

        plist["CFBundleIdentifier"]  = profile.bundle_id
        plist["CFBundleName"]        = internal
        plist["CFBundleDisplayName"] = profile.app_name

        with open(plist_path, "wb") as f:
            plistlib.dump(plist, f)

        DesktopManager._rename_helpers(app, internal, profile.bundle_id)

    @staticmethod
    def _rename_helpers(app: Path, new_name: str, bundle_id_base: str) -> None:
        """Rename Electron helpers from 'Claude Helper*' to '{new_name} Helper*'."""
        frameworks = app / "Contents" / "Frameworks"
        if not frameworks.exists():
            return
        for helper_app in sorted(frameworks.glob("Claude Helper*.app")):
            suffix   = helper_app.stem[len("Claude Helper"):]  # "", " (GPU)", etc.
            new_stem = f"{new_name} Helper{suffix}"
            new_app  = frameworks / f"{new_stem}.app"

            macos_dir = helper_app / "Contents" / "MacOS"
            old_bin = macos_dir / f"Claude Helper{suffix}"
            if old_bin.exists():
                old_bin.rename(macos_dir / new_stem)

            hp = helper_app / "Contents" / "Info.plist"
            if hp.exists():
                with open(hp, "rb") as f:
                    hplist = plistlib.load(f)
                hplist["CFBundleExecutable"]  = new_stem
                hplist["CFBundleName"]        = new_name
                hplist["CFBundleDisplayName"] = new_name
                hplist["CFBundleIdentifier"]  = f"{bundle_id_base}.helper"
                with open(hp, "wb") as f:
                    plistlib.dump(hplist, f)

            helper_app.rename(new_app)

    @staticmethod
    def _strip_signature(app: Path) -> None:
        # Re-sign with ad-hoc identity after plist edit.
        # Must sign inside-out: nested .app/.framework bundles first, outer app last.
        # --deep alone doesn't descend into nested .app bundles inside Frameworks/.
        for nested in sorted(app.rglob("*.app")) + sorted(app.rglob("*.framework")):
            _run(["codesign", "--sign", "-", "--force", str(nested)])
        _run(["codesign", "--sign", "-", "--force", str(app)])

    @staticmethod
    def _remove_quarantine(app: Path) -> None:
        # xattr -r is not available on all macOS versions; use find | xargs instead
        subprocess.run(
            f'find {str(app)!r} -print0 | xargs -0 xattr -c 2>/dev/null || true',
            shell=True,
        )
