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
- [x] **Cowork-compatible launch.** Launch the genuine, notarized
  `/Applications/Claude.app` with a per-profile `--user-data-dir` instead of copying
  and re-signing — re-signing produced an ad-hoc signature that Cowork's integrity
  check rejected ("installation appears corrupted"). Verified: Cowork VM downloads
  and runs per profile, logins stay isolated, no more "Launchd job spawn failed".

## Future

- **Clear Cowork VM (per profile).** Each profile that uses Cowork keeps its own
  ~11 GB VM under `~/Library/Application Support/Claude-<slug>/vm_bundles`. Add a
  "Clear Cowork VM" item to each profile's ⋯ menu (and a `--clear-vm <name>` CLI flag)
  that deletes that folder to reclaim space; it re-downloads on next Cowork use. The
  base OS image is fixed (~11 GB) and identical across profiles; the writable
  `sessiondata.img` is sparse and grows with use up to a cap.
- **Apple Developer ID certificate (unlocks per-profile identity).** Enroll in the
  Apple Developer Program ($99/yr) to get a "Developer ID Application" certificate.
  With a genuine Developer ID signature, a *renamed* per-profile copy
  (`Claude (Work).app`, custom `CFBundleName`/`CFBundleDisplayName` + icon) would be
  accepted by Cowork's signature check **and** show the profile name in the Dock,
  ⌘-Tab, Finder, and the Dock hover tooltip. This is the only way to get both
  per-profile identity AND working Cowork. Blocks:
    - Per-profile Dock identity (name/icon) — currently impossible: the Dock label
      comes from the bundle's *signed* `Info.plist`, and changing it requires
      re-signing, which an ad-hoc signature can't do without breaking Cowork.
    - Profile name on hover over the running app (same root cause).
    - Removing the first-launch "Open Anyway" Gatekeeper step (notarize the build).

- **Code-sign + notarize** with a Developer ID so first launch needs no right-click,
  and ship a notarized DMG / Homebrew cask in Releases.
- **Verify Cursor / Windsurf end-to-end.** The generic path is implemented and works
  for Claude; the other Electron apps are best-effort until tested on a machine that
  has them installed. Add a "Custom app…" picker for arbitrary Electron apps.
- **Per-profile menu-bar quick-launch** (optional `NSStatusItem`) in addition to the
  main window, for users who want one-click access without opening the window.
- **Profile import/export** so a setup can be moved between machines.
