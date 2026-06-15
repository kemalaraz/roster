# Roster — Architecture

## Overview

Roster lets multiple Claude Desktop and Claude Code instances run
simultaneously, each with a fully isolated account. It is a single **native
Objective-C / Cocoa** macOS app — no Python, no conda, no Swift runtime, no
bundled interpreter. The whole thing is one Mach-O binary plus an icon.

> **Why Objective-C?** The original implementation was Python (py2app + rumps),
> which forced every user through a conda build. A native rewrite removes all of
> that. Swift was the first choice, but the build host's Command Line Tools had a
> compiler/SDK version skew that made every Swift `.swiftinterface` fail to load.
> Objective-C compiles through clang (which doesn't touch swiftinterfaces), so it
> builds cleanly anywhere CLT is installed — and produces an identically native,
> dependency-free app.

## Layout

```
roster/
├── app/
│   ├── src/
│   │   ├── Models.h/.m      # Paths, AppDescriptor, Profile, ProfileStore
│   │   ├── Managers.h/.m    # Shell, DesktopManager, CodeManager, LaunchAgent
│   │   ├── UI.h/.m          # AppDelegate, MainWindowController, NewProfileSheet
│   │   └── main.m           # entry: GUI by default, CLI flags for headless use
│   ├── Info.plist
│   └── build.sh             # clang compile → assemble .app → ad-hoc sign
├── resources/icon.icns
├── Makefile                 # app / install-app / run / clean
└── build/Roster.app
```

## Build

`app/build.sh` (invoked by `make app`):

1. `clang -fobjc-arc -fmodules -framework Cocoa -mmacosx-version-min=13.0` over
   `app/src/*.m` → `Contents/MacOS/Roster`
2. Copy `Info.plist` and `icon.icns` into the bundle
3. Ad-hoc codesign the bundle

No package manager, no external libraries. Just clang and the macOS SDK.

## Isolation strategy

### Claude Desktop (`DesktopManager`)

Goal: each profile is a completely separate account with no shared session state —
**and** Cowork keeps working.

The mechanism is deliberately minimal: launch the **genuine, unmodified**
`/Applications/Claude.app` with a per-profile `--user-data-dir`:

```
open -n /Applications/Claude.app --args --user-data-dir=~/Library/Application Support/Claude-<slug>
```

- `open -n` starts a **separate instance** (Claude's single-instance lock is keyed by
  the userData dir, so distinct data dirs coexist — verified with main + 2 profiles).
- The separate data dir holds the session (cookies/localStorage), so each profile is a
  **separate login**. Verified: pointing at a fresh empty data dir opens a *logged-out*
  window, proving the session lives in the data dir, not the shared Keychain.
- The app keeps Anthropic's genuine **notarized, hardened-runtime** signature
  (`Team ID Q6L2SF6YDW`), so **Cowork's code-signature check passes**.

`setup()` therefore does almost nothing — it just ensures the data dir exists and
removes any bundle left over from the old approach. There is no copy, no plist patch,
no helper rename, no re-sign, no quarantine handling, and **no post-update sync**
(profiles always launch the current app).

> **History — why not copy the app?** v1 copied `Claude.app` per profile, patched
> `CFBundleIdentifier`/`CFBundleName`, renamed the nested Electron helpers, and ad-hoc
> re-signed inside-out. That achieved isolation, but **Cowork refused to run** in the
> re-signed bundle: Cowork runs a sandboxed Linux VM and verifies Claude's genuine
> signature first, so the ad-hoc signature (no Team ID, no notarization, no hardened
> runtime) was rejected with *"installation appears corrupted — reinstall to use
> Cowork."* Re-signing is unavoidable once you modify the bundle, so the copy approach
> and Cowork are fundamentally incompatible. The genuine-app + data-dir model avoids
> the modification entirely.

**Trade-offs:** all profiles share one bundle id, so they appear identically as
"Claude" in the Dock/⌘-Tab (no per-profile icon), and a profile is reopened via the
Roster.app rather than a standalone Desktop icon. Keychain is shared, but
since the session lives in the data dir this doesn't leak logins.

### Claude Code (`CodeManager`)

Claude Code honours `CLAUDE_CONFIG_DIR`. Each profile gets
`~/.claude-profiles/<slug>/claude-code/`. The manager resolves the real `claude`
binary (via a login shell) and opens a terminal running:

```bash
export CLAUDE_CONFIG_DIR='…/claude-code'; '<claude>'; exec bash -l
```

Ghostty is preferred (`ghostty -e bash -lc "…"`); Terminal.app is the fallback via
AppleScript. Crucially the app launches `claude` **directly** — it does not shell
out to its own CLI, so there is no dependency on anything being on `PATH` (the bug
that broke the old menu-bar build).

### Multi-app (`AppDescriptor`)

`DesktopManager` is generic over an `AppDescriptor` (app id, display name, source
path, original bundle name used for helper matching, bundle-id prefix). A registry
lists Claude (tested), Cursor, and Windsurf; any descriptor whose source app exists
is offered in the UI. The same copy/rename/sign/`--user-data-dir` flow works for any
Electron app following the standard pattern.

### Auto-sync (`LaunchAgent`)

Toggling "Auto-sync on login" writes
`~/Library/LaunchAgents/com.claudeprofiles.autosync.plist` whose `ProgramArguments`
are `[<app binary>, --sync]`, with `RunAtLoad` and a 6-hour `StartInterval`, then
`launchctl load`s it. `--sync` runs headless: for each available app whose source
version differs from the last-synced version, it re-runs the setup flow on every
installed profile.

## GUI (`UI.m`)

A single resizable `NSWindow` (not a menu-bar dropdown):

- Header: title + **Sync** + **+ New Profile**
- An update banner per app when a sync is pending
- A scrolling stack of profile cards (emoji, name, status, **Launch Desktop** /
  **Open Code** / **⋯**), built programmatically with Auto Layout
- A **New Profile** sheet (name, display name, emoji + quick-picks, app popup)
- An **Auto-sync on login** checkbox bound to `LaunchAgent`

Slow operations (bundle copy + sign) run on a background queue with the triggering
button showing a transient "Setting up…/Launching…/Syncing…" title, so the UI never
blocks.

## Entry point (`main.m`)

With no recognised arguments → `RunGUIApp()`. With CLI flags
(`--list`, `--create`, `--setup`, `--launch`, `--code`, `--sync`, `--delete`) it
runs headless and exits — used for scripting and by the auto-sync LaunchAgent.

## Data layout

```
~/.claude-profiles/
├── profiles.json          # registry: name, display, emoji, color, app_id
├── app-versions.json      # { appID: { synced_version, last_synced } }
└── <slug>/claude-code/    # CLAUDE_CONFIG_DIR per profile
~/Applications/Claude-<slug>.app                  # isolated Desktop bundle
~/Library/Application Support/Claude-<slug>/       # Electron userData per profile
~/Library/LaunchAgents/com.claudeprofiles.autosync.plist   # if auto-sync enabled
```

The `profiles.json` schema is backward-compatible with the previous Python build;
profiles without an `app_id` default to Claude.
