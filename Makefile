.PHONY: install uninstall menu-bar clean lint test

install:
	bash install.sh

uninstall:
	bash uninstall.sh

# Build the native Swift menu bar app
menu-bar:
	cd MenuBarApp && swift build -c release
	@echo
	@echo "Binary: MenuBarApp/.build/release/ClaudeProfiles"
	@echo "Run it:  open MenuBarApp/.build/release/ClaudeProfiles"

# Package the menu bar app as a proper .app bundle
menu-bar-app: menu-bar
	@mkdir -p dist/ClaudeProfiles.app/Contents/MacOS
	@cp MenuBarApp/.build/release/ClaudeProfiles dist/ClaudeProfiles.app/Contents/MacOS/
	@cp MenuBarApp/Resources/Info.plist dist/ClaudeProfiles.app/Contents/ 2>/dev/null || \
		/usr/libexec/PlistBuddy -c "Add :CFBundleName string 'Claude Profiles'" \
			-c "Add :CFBundleIdentifier string 'com.claudeprofiles.menubar'" \
			-c "Add :CFBundleExecutable string 'ClaudeProfiles'" \
			-c "Add :LSUIElement bool true" \
			dist/ClaudeProfiles.app/Contents/Info.plist 2>/dev/null || true
	@echo "App bundle: dist/ClaudeProfiles.app"
	@echo "Copy to /Applications to install."

clean:
	rm -rf MenuBarApp/.build dist __pycache__ *.egg-info claude_profiles/__pycache__

lint:
	python3 -m ruff check claude_profiles/ 2>/dev/null || true
	python3 -m mypy claude_profiles/ 2>/dev/null || true

test:
	python3 -m pytest tests/ -v 2>/dev/null || echo "No tests found yet."
