import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let store = ProfileStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(
                systemSymbolName: "person.3.fill",
                accessibilityDescription: "Claude Profiles"
            )
        }

        buildMenu()
    }

    // MARK: – Menu construction

    func buildMenu() {
        let menu = NSMenu()

        // ── header ─────────────────────────────────────────
        let title = NSMenuItem(title: "Claude Profiles", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        // ── profile entries ─────────────────────────────────
        if store.profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles — run claude-profiles create", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for profile in store.profiles {
                menu.addItem(makeProfileItem(profile))
            }
        }

        menu.addItem(.separator())

        // ── actions ─────────────────────────────────────────
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let manage = NSMenuItem(title: "Manage Profiles…", action: #selector(openTerminal), keyEquivalent: "m")
        manage.target = self
        menu.addItem(manage)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeProfileItem(_ profile: Profile) -> NSMenuItem {
        let label = "\(profile.emoji)  \(profile.displayName)"
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")

        let sub = NSMenu()

        let launchDesktop = NSMenuItem(title: "Launch Desktop", action: #selector(launchDesktop(_:)), keyEquivalent: "")
        launchDesktop.representedObject = profile.name
        launchDesktop.target = self
        if !profile.isDesktopInstalled {
            launchDesktop.title = "Launch Desktop (setup required)"
        }
        sub.addItem(launchDesktop)

        let launchCode = NSMenuItem(title: "Open Claude Code", action: #selector(launchCode(_:)), keyEquivalent: "")
        launchCode.representedObject = profile.name
        launchCode.target = self
        sub.addItem(launchCode)

        sub.addItem(.separator())

        let setupItem = NSMenuItem(title: "Setup Desktop Bundle", action: #selector(setupDesktop(_:)), keyEquivalent: "")
        setupItem.representedObject = profile.name
        setupItem.target = self
        sub.addItem(setupItem)

        item.submenu = sub
        return item
    }

    // MARK: – Actions

    @objc private func launchDesktop(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        run("launch", name)
    }

    @objc private func launchCode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openTerminalWith("claude-profiles code \(name)")
    }

    @objc private func setupDesktop(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openTerminalWith("claude-profiles setup \(name) && echo '— done —'")
    }

    @objc private func refresh(_ sender: Any) {
        store.reload()
        buildMenu()
    }

    @objc private func openTerminal(_ sender: Any) {
        openTerminalWith("claude-profiles list")
    }

    // MARK: – Helpers

    private func run(_ subcommand: String, _ arg: String) {
        let cli = store.claudeProfilesBin()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [cli, subcommand, arg]
        try? task.run()
    }

    private func openTerminalWith(_ cmd: String) {
        let safe = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(safe)"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }
}
