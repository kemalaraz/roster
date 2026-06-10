# Claude Profiles

Run multiple Claude Desktop and Claude Code accounts **simultaneously** on macOS — without logging out and back in.

Personal account, work account, a Claude Team for one client and another for a
different project. All running at the same time. Each isolated. No browser
gymnastics.

---

## How it works

**Claude Desktop** — macOS isolates apps by their *bundle identifier*
(`CFBundleIdentifier`).  Claude Profiles copies `/Applications/Claude.app` for
each profile, patches the bundle ID in `Info.plist`, and removes the code
signature.  macOS treats the copies as entirely separate apps — each gets its
own Keychain entry, its own `~/Library/Application Support/…` directory, and
its own login session.

**Claude Code** — the CLI respects the `CLAUDE_CONFIG_DIR` environment
variable.  Each profile gets its own config directory under
`~/.claude-profiles/<name>/claude-code/`, so sessions, settings, and history
are fully separate.

---

## Install

```bash
git clone https://github.com/yourusername/claude-profiles
cd claude-profiles
bash install.sh
```

The installer:
- pip-installs the `claude_profiles` package (stdlib only, no extra deps)
- Symlinks `claude-profiles` CLI into `~/.local/bin/`
- Checks for Claude Desktop and Claude Code

---

## Quick start

```bash
# Create profiles
claude-profiles create work     --emoji 💼 --color blue
claude-profiles create personal --emoji 🏠 --color green
claude-profiles create client-a --emoji 🔬 --color orange

# Set up isolated Desktop app bundles (once per profile)
claude-profiles setup work
claude-profiles setup personal

# Launch Desktop instances (all at the same time!)
claude-profiles launch work
claude-profiles launch personal

# Use Claude Code with a profile
claude-profiles code work
claude-profiles code personal

# GUI picker (AppleScript dialog — no deps)
claude-profiles open

# See what's running
claude-profiles status

# List all profiles
claude-profiles list
```

---

## CLI reference

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
| `--color` | `#0066CC` | hex code or: `blue green orange purple red teal pink yellow` |

---

## First launch (Gatekeeper)

The copied app bundles are unsigned.  macOS will block the first open with a
security warning.  Fix it one of two ways:

**Option A — right-click:**
1. In Finder, open `~/Applications/`
2. Right-click `Claude (Work).app` → **Open**
3. Click **Open** in the dialog
4. Do this once per profile

**Option B — terminal:**
```bash
xattr -d com.apple.quarantine ~/Applications/Claude-work.app
```

After that, `claude-profiles launch work` works directly.

---

## Claude Code shell wrappers

```bash
claude-profiles install
```

This writes named wrapper scripts like `claude-work`, `claude-personal`, etc.
to `~/.claude-profiles/bin/`.  Add that to PATH once:

```bash
# ~/.zshrc
export PATH="$HOME/.claude-profiles/bin:$PATH"
```

Then use them like normal `claude`:

```bash
claude-work                     # Claude Code — work profile
claude-personal "explain this"  # Claude Code — personal profile
```

---

## Menu bar app (Swift, optional)

A native macOS menu bar app shows all profiles in the menu bar and lets you
launch them with one click.

**Build:**

```bash
# Requires Xcode Command Line Tools: xcode-select --install
make menu-bar
```

**Run:**

```bash
open MenuBarApp/.build/release/ClaudeProfiles
```

Or build a proper `.app` bundle:

```bash
make menu-bar-app
cp -r dist/ClaudeProfiles.app /Applications/
```

The menu bar app reads `~/.claude-profiles/profiles.json` and calls the
`claude-profiles` CLI for all actions, so it stays in sync automatically.

---

## After a Claude Desktop update

When Anthropic ships an update, your profile app bundles become outdated.
Re-sync them (your login sessions are preserved — they live in
`~/Library/Application Support/`, not in the `.app` bundle):

```bash
# Sync all profiles
claude-profiles sync

# Or sync one profile
claude-profiles sync work
```

---

## Profile data

All profile data lives in `~/.claude-profiles/`:

```
~/.claude-profiles/
├── profiles.json          ← profile registry
├── bin/
│   ├── claude-work        ← shell wrapper
│   └── claude-personal
├── work/
│   └── claude-code/       ← CLAUDE_CONFIG_DIR for Claude Code
└── personal/
    └── claude-code/
```

Desktop login sessions are stored by macOS in
`~/Library/Application Support/com.anthropic.claude.profile.<slug>/`.

---

## Uninstall

```bash
bash uninstall.sh
```

This removes the CLI, app bundles, and wrapper scripts.
Config data in `~/.claude-profiles/` is kept by default.

---

## FAQ

**Will this break if Claude Desktop auto-updates?**
The `.app` bundle in `/Applications/Claude.app` updates normally.  Your profile
copies do not auto-update — run `claude-profiles sync` after each update.

**Does this work on Apple Silicon and Intel?**
Yes.  `shutil.copytree` preserves the universal binary as-is.

**Is removing the code signature safe?**
Yes for personal use.  The signature is only used by macOS Gatekeeper to verify
the app came from Anthropic — it does not affect functionality.  You are running
a local copy on your own machine.

**What about Claude Desktop's auto-updater?**
The updater in each profile copy will try to update itself, but because the
bundle ID is different from the store copy the update will fail silently.  Just
run `claude-profiles sync` after you see Anthropic has shipped an update.

**My `claude-profiles code` command says `exec: claude: not found`.**
Make sure the Claude Code CLI is installed:
```bash
npm install -g @anthropic-ai/claude-code
```
Or set the full path: `export CLAUDE_BIN=/path/to/claude`.

---

## Contributing

PRs welcome.  The codebase is small on purpose:

- `claude_profiles/desktop.py` — app bundle cloning/patching
- `claude_profiles/code.py` — Claude Code isolation
- `claude_profiles/cli.py` — CLI commands
- `claude_profiles/gui.py` — AppleScript picker
- `MenuBarApp/` — native Swift menu bar app

---

## License

MIT
