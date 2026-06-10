"""Main CLI entry-point for claude-profiles."""
from __future__ import annotations
import sys
import argparse
from pathlib import Path

from .profile import PRESET_COLORS, PRESET_EMOJIS, PROFILES_DIR
from .manager import ProfileManager
from .desktop import DesktopManager
from .code import CodeManager
from .gui import pick_profile, pick_action, notify


# ──────────────────────────────────────────────────────────────────────────────
# helpers
# ──────────────────────────────────────────────────────────────────────────────

def _ok(msg: str): print(f"✓ {msg}")
def _err(msg: str): print(f"✗ {msg}", file=sys.stderr)
def _die(msg: str):
    _err(msg)
    sys.exit(1)


def _require_profile(pm: ProfileManager, name: str):
    p = pm.get(name)
    if not p:
        _die(f"Profile '{name}' not found — run: claude-profiles list")
    return p


# ──────────────────────────────────────────────────────────────────────────────
# commands
# ──────────────────────────────────────────────────────────────────────────────

def cmd_list(pm: ProfileManager, **_):
    dm = DesktopManager()
    _warn_if_update_pending(dm)
    profiles = pm.list()
    if not profiles:
        print("No profiles yet. Create one:\n  claude-profiles create work --emoji 💼")
        return
    w = max(len(p.display_name) for p in profiles) + 2
    header = f"  {'PROFILE':<18} {'DISPLAY':<{w}} {'DESKTOP':^8} {'CODE':^6}"
    print(header)
    print("  " + "─" * (len(header) - 2))
    for p in profiles:
        desktop = "✓" if p.is_desktop_installed else "·"
        code    = "✓" if p.is_code_initialized  else "·"
        print(f"  {p.name:<18} {p.emoji} {p.display_name:<{w-2}} {desktop:^8} {code:^6}")
    print()


def _warn_if_update_pending(dm: DesktopManager) -> None:
    pending = dm.update_available()
    if pending:
        old, new = pending
        print(f"⚠️  Claude Desktop updated: v{old} → v{new}. Run: claude-profiles sync")
        print()


def cmd_create(pm: ProfileManager, args, **_):
    color = PRESET_COLORS.get(args.color, args.color)
    try:
        profile = pm.create(
            name=args.name,
            display_name=args.display_name or args.name.capitalize(),
            color=color,
            emoji=args.emoji,
        )
    except ValueError as e:
        _die(str(e))

    _ok(f"Created profile '{profile.display_name}' [{profile.name}]")
    print(f"  Config dir  : {profile.profile_dir}")
    print()
    print("Next steps:")
    print(f"  Setup Desktop : claude-profiles setup {profile.name}")
    print(f"  Launch Desktop: claude-profiles launch {profile.name}")
    print(f"  Claude Code   : claude-profiles code {profile.name}")
    print()
    print("Or open the picker:")
    print("  claude-profiles open")


def cmd_delete(pm: ProfileManager, args, **_):
    profile = _require_profile(pm, args.name)
    if not args.force:
        ans = input(f"Delete '{profile.display_name}' and all its data? [y/N] ")
        if ans.lower() != "y":
            print("Aborted.")
            return
    keep = getattr(args, "keep_data", False)
    pm.delete(args.name, keep_data=keep)
    _ok(f"Deleted '{profile.display_name}'")


def cmd_setup(pm: ProfileManager, args, **_):
    profile = _require_profile(pm, args.name)
    dm = DesktopManager()
    print(f"Setting up Desktop app for '{profile.display_name}' …")
    try:
        path = dm.setup(profile, force=getattr(args, "force", False))
    except FileNotFoundError as e:
        _die(str(e))
    _ok(f"App ready: {path}")
    print()
    print("First launch — Gatekeeper will ask you to confirm:")
    print(f"  Right-click → Open  (or run: xattr -d com.apple.quarantine \"{path}\")")


def cmd_launch(pm: ProfileManager, args, **_):
    profile = _require_profile(pm, args.name)
    dm = DesktopManager()
    try:
        dm.launch(profile)
    except FileNotFoundError as e:
        _die(str(e))
    _ok(f"Launched {profile.app_name}")


def cmd_code(pm: ProfileManager, args, **_):
    profile = _require_profile(pm, args.name)
    cm = CodeManager()
    extra = getattr(args, "rest", [])
    # execvpe — does not return
    cm.launch(profile, extra_args=extra)


def cmd_install(pm: ProfileManager, **_):
    """Write wrapper scripts for all profiles and print PATH instructions."""
    cm = CodeManager()
    for p in pm.list():
        wp = cm.setup(p)
        _ok(f"claude-{p.slug}  →  {wp}")
    bin_dir = cm.bin_dir()
    print()
    print("Add to ~/.zshrc (or ~/.bash_profile):")
    print(f'  export PATH="{bin_dir}:$PATH"')
    print()
    print("Then reload and call:")
    for p in pm.list():
        print(f"  claude-{p.slug}        # {p.display_name} profile")


def cmd_sync(pm: ProfileManager, args, **_):
    dm = DesktopManager()
    if hasattr(args, "name") and args.name:
        profiles = [_require_profile(pm, args.name)]
    else:
        profiles = [p for p in pm.list() if p.is_desktop_installed]
    if not profiles:
        print("No installed Desktop profiles to sync.")
        return
    src_version = dm.source_version()
    print(f"Source Claude version: {src_version or '(unknown)'}")
    dm.sync_all(profiles)
    _ok("Sync complete")


def cmd_open(pm: ProfileManager, **_):
    """AppleScript GUI picker."""
    profile = pick_profile(pm.list())
    if not profile:
        return
    action = pick_action(profile)
    if not action:
        return

    if action == "desktop":
        dm = DesktopManager()
        try:
            dm.launch(profile)
            notify("Claude Profiles", f"Launched {profile.app_name}")
        except FileNotFoundError as e:
            _die(str(e))
    elif action == "code":
        cm = CodeManager()
        cm.launch(profile)


def cmd_status(pm: ProfileManager, **_):
    dm = DesktopManager()
    _warn_if_update_pending(dm)
    profiles = pm.list()
    if not profiles:
        print("No profiles.")
        return
    print(f"\n  {'PROFILE':<20} {'DESKTOP RUNNING':^16} {'APP INSTALLED':^14}")
    print("  " + "─" * 54)
    for p in profiles:
        running   = "● running" if dm.is_running(p) else "○ stopped"
        installed = "✓" if p.is_desktop_installed else "✗ not set up"
        print(f"  {p.display_name:<20} {running:^16} {installed:^14}")
    print()


# ──────────────────────────────────────────────────────────────────────────────
# entry-point
# ──────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="claude-profiles",
        description="Run multiple Claude Desktop / Code accounts simultaneously on macOS.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  claude-profiles create work --emoji 💼 --color blue
  claude-profiles create personal --emoji 🏠 --color green
  claude-profiles setup work
  claude-profiles launch work
  claude-profiles code work
  claude-profiles open          # GUI picker
  claude-profiles list
  claude-profiles sync          # re-copy after Claude updates
""",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")
    sub.required = True

    # list
    sub.add_parser("list", aliases=["ls"], help="List all profiles")

    # create
    c = sub.add_parser("create", help="Create a new profile")
    c.add_argument("name", help="Short identifier, e.g. 'work' or 'personal'")
    c.add_argument("--display-name", "-d", dest="display_name", help="Human-readable name")
    c.add_argument("--color", "-c", default="#0066CC",
                   help=f"Hex colour or name ({', '.join(PRESET_COLORS)})")
    c.add_argument("--emoji", "-e", default="👤", help="Emoji icon shown in the menu bar app")

    # delete
    d = sub.add_parser("delete", aliases=["rm"], help="Delete a profile")
    d.add_argument("name")
    d.add_argument("--force", "-f", action="store_true", help="Skip confirmation prompt")
    d.add_argument("--keep-data", action="store_true", help="Remove app bundle but keep config data")

    # setup
    s = sub.add_parser("setup", help="Create isolated Desktop app bundle for a profile")
    s.add_argument("name")
    s.add_argument("--force", "-f", action="store_true", help="Re-copy even if already set up")

    # launch
    la = sub.add_parser("launch", aliases=["desktop"], help="Launch Claude Desktop for a profile")
    la.add_argument("name")

    # code
    co = sub.add_parser("code", help="Start Claude Code with a profile's config dir")
    co.add_argument("name")
    co.add_argument("rest", nargs=argparse.REMAINDER, help="Extra args passed to claude")

    # open  (GUI picker)
    sub.add_parser("open", aliases=["gui", "pick"], help="AppleScript picker — choose profile + action")

    # install
    sub.add_parser("install", help="Write named shell wrappers (claude-work, claude-personal, …)")

    # sync
    sy = sub.add_parser("sync", help="Re-copy Desktop bundles after a Claude update")
    sy.add_argument("name", nargs="?", help="Specific profile (default: all installed)")

    # status
    sub.add_parser("status", help="Show which Desktop profiles are currently running")

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    pm = ProfileManager()
    cmd = args.command

    dispatch = {
        "list":    cmd_list,   "ls":      cmd_list,
        "create":  cmd_create,
        "delete":  cmd_delete, "rm":      cmd_delete,
        "setup":   cmd_setup,
        "launch":  cmd_launch, "desktop": cmd_launch,
        "code":    cmd_code,
        "open":    cmd_open,   "gui":     cmd_open,   "pick": cmd_open,
        "install": cmd_install,
        "sync":    cmd_sync,
        "status":  cmd_status,
    }

    fn = dispatch.get(cmd)
    if fn:
        fn(pm=pm, args=args)
    else:
        parser.print_help()
        sys.exit(1)
