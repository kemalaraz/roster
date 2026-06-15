.PHONY: app install-app run clean

APP := build/Roster.app

# ── Build the standalone native app (no dependencies beyond Xcode CLT) ───────
app:
	bash app/build.sh

# ── Build + install to /Applications + clear quarantine + launch ─────────────
install-app: app
	@echo "→ Stopping any running instance…"
	@pkill -f "Roster.app/Contents/MacOS/Roster" 2>/dev/null || true
	@pkill -f "Claude Profiles.app/Contents/MacOS/ClaudeProfiles" 2>/dev/null || true
	@sleep 1
	@echo "→ Installing to /Applications…"
	@rm -rf "/Applications/Roster.app"
	@rm -rf "/Applications/Claude Profiles.app"   # remove the old-named bundle
	@cp -R "$(APP)" "/Applications/Roster.app"
	@echo "→ Clearing Gatekeeper quarantine…"
	@find "/Applications/Roster.app" -print0 | xargs -0 xattr -c 2>/dev/null || true
	@echo "→ Launching…"
	@open "/Applications/Roster.app"
	@sleep 2
	@pgrep -f "Roster.app/Contents/MacOS/Roster" > /dev/null \
		&& echo "✓ Roster is running" \
		|| echo "✗ App did not start — check Console.app"

# ── Build + run straight from build/ (for development) ───────────────────────
run: app
	@pkill -f "Roster.app/Contents/MacOS/Roster" 2>/dev/null || true
	@open "$(APP)"

clean:
	rm -rf build dist
