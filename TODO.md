# TODO

## Done

- [x] **Standalone, dependency-free app.** Rewritten from Python (py2app + conda +
  rumps) to native Objective-C / Cocoa. One Mach-O binary, no runtime deps. Builds
  with just the Xcode Command Line Tools.
- [x] **Multi-app support.** `DesktopManager` is generic over `AppDescriptor`;
  Claude (tested), Cursor, and Windsurf are registered and auto-detected.
- [x] **Auto-sync on login.** `LaunchAgent` writes a plist that runs `--sync` at
  login + every 6 hours; toggled from the GUI.
- [x] **Simple windowed GUI** instead of a menu-bar dropdown.

## Future

- **Code-sign + notarize** with a Developer ID so first launch needs no right-click,
  and ship a notarized DMG / Homebrew cask in Releases.
- **Verify Cursor / Windsurf end-to-end.** The generic path is implemented and works
  for Claude; the other Electron apps are best-effort until tested on a machine that
  has them installed. Add a "Custom app…" picker for arbitrary Electron apps.
- **Per-profile menu-bar quick-launch** (optional `NSStatusItem`) in addition to the
  main window, for users who want one-click access without opening the window.
- **Profile import/export** so a setup can be moved between machines.
