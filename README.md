# Claude Profiles

Run multiple Claude Desktop and Claude Code accounts **simultaneously** on macOS — without logging out and back in.

Personal account, work account, a Claude Team for one client and another for a
different project. All running at the same time, each fully isolated. No browser
gymnastics.

A single native macOS app. **No Python, no conda, no runtime dependencies** —
just download and double-click.

---

## Install

### Option A — download the app

1. Download `Claude Profiles.app` (from Releases, or build it — see below).
2. Drag it to `/Applications`.
3. First launch: right-click → **Open** (macOS asks once, because the app is ad-hoc signed).

### Option B — build from source

Requires only the **Xcode Command Line Tools** (`xcode-select --install`) — no
Python, no conda, no full Xcode.

```bash
git clone https://github.com/kemalaraz/claude-profiles
cd claude-profiles
make install-app
```

`make install-app` compiles the app with `clang`, installs it to `/Applications`,
clears the Gatekeeper quarantine flag, and launches it.

---

## Using it

The app opens a simple window listing your profiles.

- **+ New Profile** — name it, pick an emoji, choose the app (Claude, or any other
  supported Electron app you have installed). Created instantly.
- **Launch Desktop** — opens a fully isolated Claude Desktop for that account.
  The first time, it sets up the isolated bundle (a few seconds).
- **Open Code** — opens a terminal (Ghostty if installed, else Terminal.app)
  running `claude` against that profile's isolated config.
- **⋯** — re-setup the bundle, reveal it in Finder, or delete the profile.
- **Sync** — re-copies profile bundles after Claude Desktop updates.
- **Auto-sync on login** — installs a LaunchAgent that keeps profiles in sync
  automatically whenever Claude updates.

---

## How it works

**Claude Desktop isolation.** Each profile gets a copy of `/Applications/Claude.app`
at `~/Applications/Claude-<name>.app`, with three changes that make it a genuinely
separate app:

1. **`CFBundleIdentifier`** → `com.anthropic.claude.profile.<name>` — macOS scopes
   Keychain entries by bundle id, so credentials never leak between profiles.
2. **`CFBundleName`** → `Claude-<name>`, and every nested Electron helper
   (`Claude Helper.app`, `Claude Helper (GPU).app`, …) is renamed to match —
   Electron derives helper paths from `CFBundleName`, so this is required for the
   app to launch at all.
3. **`--user-data-dir`** is passed at launch, pointing at
   `~/Library/Application Support/Claude-<name>` — this gives each profile its own
   cookies, localStorage, and session, which is what actually separates the accounts.

The bundle is then ad-hoc re-signed **inside-out** (nested helpers first, outer app
last — `--deep` alone doesn't descend into nested `.app` bundles) and de-quarantined.

**Claude Code isolation.** Claude Code honours `CLAUDE_CONFIG_DIR`. Each profile
gets `~/.claude-profiles/<name>/claude-code/`, so sessions, settings, and history
are entirely separate. The app launches `claude` directly with that env var set —
no PATH wrapper required.

**Multi-app.** The isolation logic is generic over an `AppDescriptor`, so the same
mechanism works for any Electron app following the standard helper/`--user-data-dir`
pattern. Claude is fully tested; Cursor and Windsurf are detected automatically if
installed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.

---

## CLI

The same binary doubles as a CLI (handy for scripting; also what the auto-sync
LaunchAgent calls):

```bash
CP="/Applications/Claude Profiles.app/Contents/MacOS/ClaudeProfiles"

"$CP" --list                      # list profiles + status
"$CP" --create work --emoji 💼    # create a profile
"$CP" --setup work [--force]      # build/refresh its isolated bundle
"$CP" --launch work               # launch its Desktop app
"$CP" --code work                 # open Claude Code for it
"$CP" --sync                      # re-sync all installed bundles after an update
"$CP" --delete work               # remove profile + bundle
```

Running it with no arguments opens the GUI.

---

## After a Claude Desktop update

Profile bundles don't auto-update. Click **Sync** in the app (or run `--sync`, or
enable **Auto-sync on login**). Login sessions live in
`~/Library/Application Support/Claude-<name>` and are preserved across syncs.

---

## Profile data layout

```
~/.claude-profiles/
├── profiles.json              ← profile registry
├── app-versions.json          ← last-synced version per app
└── work/
    └── claude-code/           ← CLAUDE_CONFIG_DIR for the work profile

~/Applications/
├── Claude-work.app            ← isolated Desktop app (work)
└── Claude-personal.app        ← isolated Desktop app (personal)

~/Library/Application Support/
├── Claude-work/               ← Desktop session + data (work)
└── Claude-personal/           ← Desktop session + data (personal)
```

---

## FAQ

**Do I need Python, conda, or Xcode?**
No. The app is a native Objective-C/Cocoa binary with zero runtime dependencies.
Building from source needs only the Xcode Command Line Tools (`clang`).

**Does it work on Apple Silicon and Intel?**
Yes — it copies `Claude.app` as-is, preserving its universal binary.

**`Open Code` says `claude: not found`.**
Install Claude Code: `npm install -g @anthropic-ai/claude-code`.

---

## License

MIT
