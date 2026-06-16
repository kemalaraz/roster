# Roster

Run multiple Claude Desktop and Claude Code accounts **simultaneously** on macOS — without logging out and back in.

Personal account, work account, a Claude Team for one client and another for a
different project. All running at the same time, each fully isolated. No browser
gymnastics.

A single native macOS app. **No Python, no conda, no runtime dependencies** —
just download and double-click.

---

> **Requirement:** [Claude Desktop](https://claude.ai/download) must be installed at
> `/Applications/Claude.app` — the tool launches the genuine app per profile.

### Option A — download the prebuilt app

1. Go to the **[latest release](https://github.com/kemalaraz/roster/releases/latest)**
   and download `Roster.app.zip`.
2. Unzip it and drag **Roster.app** to `/Applications`.
3. First launch: double-click it, then approve it once in
   **System Settings → Privacy & Security → "Open Anyway"** (the app is ad-hoc
   signed, not notarized, so macOS asks the first time — see
   [First launch](#first-launch--gatekeeper) below).

### Option B — build from source

Requires only the **Xcode Command Line Tools** (`xcode-select --install`) — no
Python, no conda, no full Xcode.

```bash
git clone https://github.com/kemalaraz/roster
cd roster
make install-app
```

`make install-app` compiles the app with `clang`, installs it to `/Applications`,
clears the Gatekeeper quarantine flag, and launches it. (Built locally, so no
Gatekeeper prompt.)

### First launch — Gatekeeper

A **downloaded** copy is tagged by the browser, so the first launch is blocked with
"unverified developer." Approve it once: **System Settings → Privacy & Security**,
scroll to the "Roster was blocked" notice, click **Open Anyway**, then
launch again. (On macOS 14 and earlier you can instead right-click the app → **Open**.)
This is only because the app isn't notarized with a paid Apple Developer ID; building
from source (Option B) avoids it entirely.

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

**Claude Desktop isolation.** Each profile launches the **genuine, unmodified**
`/Applications/Claude.app` with its own `--user-data-dir`:

```
open -n /Applications/Claude.app --args --user-data-dir=~/Library/Application Support/Claude-<name>
```

The separate data dir gives each profile its own cookies, localStorage, and session —
that's what separates the accounts (verified: a fresh data dir starts logged out, so
the session lives in the data dir, not the shared Keychain). Because the app itself is
never copied or modified, it keeps Anthropic's genuine notarized signature.

> **Why not copy the app?** An earlier version copied `Claude.app` per profile and
> patched/re-signed it. That works for plain isolation, but **Cowork refuses to run**
> in a re-signed bundle — it verifies Claude's genuine code signature, and re-signing
> (required to change the bundle id / rename Electron helpers) replaces it with an
> ad-hoc signature. Launching the genuine app with a per-profile data dir keeps Cowork
> working, survives Claude updates with no re-sync, and avoids the macOS
> "Launchd job spawn failed" errors that re-signing caused.

**Trade-off:** since every profile is the same genuine bundle, they all appear as
"Claude" in the Dock/⌘-Tab (no per-profile icon), and you reopen a profile via the
Roster.app rather than a standalone Desktop icon.

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
CP="/Applications/Roster.app/Contents/MacOS/Roster"

"$CP" --list                      # list profiles + status
"$CP" --create work --emoji 💼    # create a profile
"$CP" --setup work [--force]      # build/refresh its isolated bundle
"$CP" --launch work               # launch its Desktop app
"$CP" --code work                 # open Claude Code for it
"$CP" --sync                      # re-sync all installed bundles after an update
"$CP" --delete work               # remove profile + bundle
```

Running it with no arguments opens the GUI.

### Terminal profile picker

Install shims so typing `claude` (and `codex`, once installed) in any terminal pops a
small styled picker — choose a profile and it runs the real CLI with that profile's
config, and titles the window with the account:

```bash
bash tools/install-cli.sh     # adds ~/.roster/bin to PATH; open a new terminal
claude                        # ↑/↓ pick a profile (remembers your last choice)
claude --profile work         # skip the prompt
```

It stays out of the way: non-interactive use (scripts/pipes) and anything launched
with `CLAUDE_CONFIG_DIR`/`CODEX_HOME` already set pass straight through to the real
binary with no prompt. "Default" always gives you your plain global `~/.claude`, and
**Esc cancels** (opens nothing).

> Already-open terminals won't see the picker until you **open a new terminal**
> (they loaded `PATH` before the install). Run **`roster doctor`** to check setup —
> it verifies the shim, PATH, real binary, and tells you if this shell needs a restart.

---

## After a Claude Desktop update

Nothing to do — profiles launch the current `/Applications/Claude.app` directly, so a
Claude update applies to every profile automatically. (No copied bundles to re-sync.)

---

## Profile data layout

```
~/.claude-profiles/
├── profiles.json              ← profile registry
└── work/
    └── claude-code/           ← CLAUDE_CONFIG_DIR for the work profile

~/Library/Application Support/
├── Claude-work/               ← Desktop session + data + Cowork VM (work)
└── Claude-personal/           ← Desktop session + data + Cowork VM (personal)
```

The genuine `/Applications/Claude.app` is shared by all profiles; only the per-profile
data dir differs.

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

**Proprietary — All Rights Reserved.** Copyright © 2026 Kemal Araz.

This software may not be used, run, copied, modified, or distributed without the
author's prior written permission. Viewing or forking the source on GitHub does
**not** grant any right to use it. See [LICENSE](LICENSE). To request permission,
contact kemalaraz91@gmail.com.
