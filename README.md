# Claude Profiles

Run multiple Claude Desktop and Claude Code accounts **simultaneously** on macOS — without logging out and back in.

Personal account, work account, a Claude Team for one client and another for a
different project. All running at the same time. Each fully isolated. No browser
gymnastics.

---

## Install

> Requires Xcode Command Line Tools (`xcode-select --install`) and Python 3 (ships with macOS).

```bash
git clone https://github.com/kemalaraz/claude-profiles
cd claude-profiles
make app                     # builds dist/Claude Profiles.app
cp -r "dist/Claude Profiles.app" /Applications/
open "/Applications/Claude Profiles.app"
```

That's it. The menu bar icon appears. Click it.

---

## First launch

The **New Profile** window opens automatically when you have no profiles yet.

1. Fill in a name, pick an emoji and colour, check "Set up Desktop bundle"
2. Click **Create Profile**
3. The profile appears in the menu bar — click it to launch Desktop or Claude Code

No terminal needed for day-to-day use.

![menu bar screenshot placeholder](docs/screenshot.png)

---

## Menu bar app

The `.app` is self-contained — the Python backend is bundled inside it.
You do not need to install anything else to use the GUI.

| Menu item | What it does |
|-----------|--------------|
| **⌘N  New Profile…** | Opens the profile creation form |
| `💼  Work` → Launch Desktop | Opens an isolated Claude Desktop for that account |
| `💼  Work` → Open Claude Code | Opens a Terminal tab with Claude Code pointed at that profile |
| `💼  Work` → Setup Desktop Bundle | (Re-)creates the app bundle if not done yet |
| Refresh | Reloads profiles from disk |
| Open Terminal | Opens a Terminal with `claude-profiles list` |

---

## How it works

**Claude Desktop isolation** — macOS sandboxes apps by bundle identifier.
Claude Profiles copies `/Applications/Claude.app` for each profile and patches
the `CFBundleIdentifier` in `Info.plist`. macOS then creates a completely
separate Keychain entry and `~/Library/Application Support/` directory per
profile, so each one gets its own login session.

**Claude Code isolation** — the CLI respects the `CLAUDE_CONFIG_DIR`
environment variable. Each profile gets its own directory under
`~/.claude-profiles/<name>/claude-code/`, so sessions, settings, and history
are entirely separate.

---

## CLI reference

The `claude-profiles` CLI is also available for scripting and automation.

```bash
# Install CLI (optional — already bundled inside the .app)
bash install.sh
```

| Command | Description |
|---------|-------------|
| `create <name>` | Create a new profile |
| `list` | List all profiles with setup status |
| `setup <name>` | Copy + patch the Desktop app bundle |
| `launch <name>` | Open Claude Desktop for a profile |
| `code <name> [args…]` | Run Claude Code for a profile |
| `open` | AppleScript GUI picker |
| `status` | Show which Desktop profiles are running |
| `sync [name]` | Re-copy Desktop bundles after a Claude update |
| `install` | Write `claude-<slug>` shell wrappers for Claude Code |
| `delete <name>` | Remove a profile and its app bundle |

**`create` options:**

| Flag | Default | Values |
|------|---------|--------|
| `--display-name` | capitalized name | any string |
| `--emoji` | 👤 | any emoji |
| `--color` | `#0066CC` | hex or: `blue green orange purple red teal pink yellow` |

---

## First launch — Gatekeeper

The copied Desktop app bundles are unsigned. macOS blocks unsigned apps by
default. Fix it once per profile:

**Option A — right-click:**
Open `~/Applications/`, right-click `Claude (Work).app` → **Open** → **Open**.

**Option B — terminal:**
```bash
xattr -d com.apple.quarantine ~/Applications/Claude-work.app
```

After that, `claude-profiles launch work` and the menu bar app both work
without prompts.

---

## Claude Code shell wrappers

```bash
claude-profiles install
```

Writes named wrappers (`claude-work`, `claude-personal`, …) to
`~/.claude-profiles/bin/`. Add to PATH once:

```bash
# ~/.zshrc
export PATH="$HOME/.claude-profiles/bin:$PATH"
```

---

## After a Claude Desktop update

Profile app bundles don't auto-update. Re-sync after Anthropic ships an update:

```bash
claude-profiles sync        # re-copies all installed profiles from source
```

Login sessions are stored in `~/Library/Application Support/` and are
preserved across syncs.

---

## Profile data layout

```
~/.claude-profiles/
├── profiles.json               ← profile registry
├── bin/
│   ├── claude-work             ← shell wrapper for Claude Code
│   └── claude-personal
├── work/
│   └── claude-code/            ← CLAUDE_CONFIG_DIR for work profile
└── personal/
    └── claude-code/

~/Applications/
├── Claude-work.app             ← isolated Desktop app (work)
└── Claude-personal.app         ← isolated Desktop app (personal)

~/Library/Application Support/
├── com.anthropic.claude.profile.work/      ← Desktop login + data (work)
└── com.anthropic.claude.profile.personal/  ← Desktop login + data (personal)
```

---

## Building from source

```bash
# Requirements: Xcode CLT, Python 3
xcode-select --install        # if not already installed

make app                      # → dist/Claude Profiles.app
make install-app              # build + copy to /Applications
make clean                    # remove build artifacts
```

---

## FAQ

**Do I need Python installed separately?**
No. The `.app` bundles the Python scripts inside itself. Python 3 ships with
macOS and is only invoked at runtime, not at install time.

**Does this work on Apple Silicon and Intel?**
Yes. The app bundle copies Claude.app as-is, preserving the universal binary.

**What happens when Claude Desktop auto-updates?**
The main `/Applications/Claude.app` updates normally. Profile copies do not —
run `claude-profiles sync` (or use "Setup Desktop Bundle" in the menu) after
each update.

**My `claude-profiles code` says `exec: claude: not found`.**
Install Claude Code: `npm install -g @anthropic-ai/claude-code`

---

## License

MIT
