"""AppleScript-based profile picker — zero external dependencies."""
from __future__ import annotations
import subprocess
import sys
from typing import Optional

from .profile import Profile


def _osascript(script: str) -> Optional[str]:
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return r.stdout.strip() or None


def pick_profile(profiles: list[Profile]) -> Optional[Profile]:
    """Show a macOS list-picker and return the chosen Profile, or None."""
    if not profiles:
        _osascript(
            'display dialog "No profiles found.\\n\\nRun:\\n  claude-profiles create <name>" '
            'buttons {"OK"} default button "OK" with title "Claude Profiles"'
        )
        return None

    items_as = "{" + ", ".join(f'"{p.emoji}  {p.display_name}"' for p in profiles) + "}"
    script = f"""
set profileList to {items_as}
set chosen to choose from list profileList ¬
    with title "Claude Profiles" ¬
    with prompt "Select a profile:" ¬
    default items {{item 1 of profileList}} ¬
    without multiple selections allowed and empty selection allowed
if chosen is false then return ""
return item 1 of chosen
"""
    result = _osascript(script)
    if not result:
        return None

    # Match chosen label back to profile by display_name
    for p in profiles:
        if p.display_name in result:
            return p
    return None


def pick_action(profile: Profile) -> Optional[str]:
    """Ask the user what to do with the chosen profile. Returns 'desktop', 'code', or None."""
    script = f"""
set chosen to choose from list {{"Launch Desktop", "Open Claude Code"}} ¬
    with title "{profile.emoji}  {profile.display_name}" ¬
    with prompt "What would you like to open?" ¬
    default items {{"Launch Desktop"}} ¬
    without multiple selections allowed and empty selection allowed
if chosen is false then return ""
return item 1 of chosen
"""
    result = _osascript(script)
    if not result:
        return None
    if "Desktop" in result:
        return "desktop"
    if "Code" in result:
        return "code"
    return None


def notify(title: str, message: str) -> None:
    _osascript(
        f'display notification "{message}" with title "{title}"'
    )
