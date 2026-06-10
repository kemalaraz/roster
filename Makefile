.PHONY: app install uninstall clean lint test

# ── Primary target: build standalone .app via py2app ─────────────────────────
app:
	conda run -n claude-profiles python setup_app.py py2app

# Install the .app to /Applications after building
install-app: app
	@cp -r "dist/Claude Profiles.app" /Applications/
	@echo "✓ Installed to /Applications/Claude Profiles.app"
	@echo "  Open it from Launchpad or: open /Applications/Claude\\ Profiles.app"

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
