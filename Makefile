.PHONY: app install-app run clean

APP := build/Claude Profiles.app

# ── Build the standalone native app (no dependencies beyond Xcode CLT) ───────
app:
	bash app/build.sh

# ── Build + install to /Applications + clear quarantine + launch ─────────────
install-app: app
	@echo "→ Stopping any running instance…"
	@pkill -f "Claude Profiles.app/Contents/MacOS/ClaudeProfiles" 2>/dev/null || true
	@sleep 1
	@echo "→ Installing to /Applications…"
	@rm -rf "/Applications/Claude Profiles.app"
	@cp -R "$(APP)" "/Applications/Claude Profiles.app"
	@echo "→ Clearing Gatekeeper quarantine…"
	@find "/Applications/Claude Profiles.app" -print0 | xargs -0 xattr -c 2>/dev/null || true
	@echo "→ Launching…"
	@open "/Applications/Claude Profiles.app"
	@sleep 2
	@pgrep -f "Claude Profiles.app/Contents/MacOS/ClaudeProfiles" > /dev/null \
		&& echo "✓ Claude Profiles is running" \
		|| echo "✗ App did not start — check Console.app"

# ── Build + run straight from build/ (for development) ───────────────────────
run: app
	@pkill -f "ClaudeProfiles" 2>/dev/null || true
	@open "$(APP)"

clean:
	rm -rf build dist
