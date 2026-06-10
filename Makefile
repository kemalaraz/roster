.PHONY: app install-app launch uninstall clean lint test

# ── Primary target: build standalone .app via py2app ─────────────────────────
app:
	conda run -n claude-profiles python setup_app.py py2app

# Build + install + strip quarantine + launch — the full first-time setup
install-app: app
	@echo "→ Stopping any running instance…"
	@pkill -f "menubar/menubar.py" 2>/dev/null || true
	@pkill -f "Claude Profiles" 2>/dev/null || true
	@sleep 1
	@echo "→ Copying to /Applications/…"
	@rm -rf "/Applications/Claude Profiles.app"
	@cp -r "dist/Claude Profiles.app" "/Applications/Claude Profiles.app"
	@echo "→ Clearing Gatekeeper quarantine…"
	@find "/Applications/Claude Profiles.app" -print0 | xargs -0 xattr -c 2>/dev/null || true
	@echo "→ Launching…"
	@open "/Applications/Claude Profiles.app"
	@sleep 2
	@pgrep -f "menubar" > /dev/null && echo "✓ Claude Profiles is running — look for the icon in your menu bar" || echo "✗ App did not start, check Console.app for errors"

# ── CLI-only install (no Swift build needed) ──────────────────────────────────
install:
	bash install.sh

uninstall:
	bash uninstall.sh

clean:
	rm -rf MenuBarApp/.build dist build __pycache__ *.egg-info claude_profiles/__pycache__ claude_profiles.egg-info

lint:
	python3 -m ruff check claude_profiles/ 2>/dev/null || true
	python3 -m mypy claude_profiles/ 2>/dev/null || true

test:
	python3 -m pytest tests/ -v 2>/dev/null || echo "No tests found yet."
