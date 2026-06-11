# TODO

## Standalone binary (remove Python/conda dependency)

Currently building the menu bar app requires a conda environment with Python 3.11, rumps, pyobjc, and py2app. This creates a heavy install burden.

**Goal**: ship a single downloadable binary with no runtime dependencies.

Options:
- **PyInstaller `--onefile`**: produces a self-extracting binary. Still Python under the hood but zero install friction for the end user.
- **Native Swift rewrite**: rewrite the menu bar app in Swift using `MenuBarExtra` (macOS 13+). The `claude_profiles` Python library can be called via a subprocess or replaced with equivalent Swift code. Eliminates Python entirely.
- **Nuitka**: compiles Python to C and then to a native binary. More complex but avoids the PyInstaller "explode on first run" cost.

The CLI (`claude-profiles`) can stay Python for now since developers will have Python anyway; the menu bar `.app` is the user-facing piece that needs to be dependency-free.

---

## Extend to other apps (Codex, Cursor, etc.)

The same isolation technique (copy app → rename helpers → patch bundle ID → set userData dir) works for any Electron-based app.

Candidates:
- **OpenAI Codex Desktop** — identical Electron pattern
- **Cursor** — Electron-based VS Code fork
- **Windsurf** — same
- **GitHub Copilot Desktop** — same

Implementation approach:
- Add an `AppDescriptor` dataclass (`source_app`, `bundle_id_prefix`, `app_name_prefix`) to `profile.py`
- Make `DesktopManager` generic over `AppDescriptor` instead of hardcoding Claude paths
- Update the CLI and menu bar to let users associate profiles with any registered app

---

## LaunchAgent for auto-sync

When Claude Desktop auto-updates, existing profile bundles go stale and need `claude-profiles sync`. Currently this is manual.

Add a macOS LaunchAgent plist that runs `claude-profiles sync --if-needed` on login and/or on a schedule, so profiles stay current automatically.
