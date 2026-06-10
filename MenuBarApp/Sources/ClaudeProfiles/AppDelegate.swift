import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let store        = ProfileStore()
    private let updateChecker = UpdateChecker()
    private var newProfilePanel: NSPanel?
    private var isSyncing = false

    // MARK: – Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon(syncing: false)
        buildMenu()

        // Auto-open New Profile window on very first launch
        if store.profiles.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.openNewProfileWindow()
            }
        }

        // Start watching for Claude Desktop updates
        updateChecker.onUpdateDetected = { [weak self] old, new in
            self?.promptForSync(from: old, to: new)
        }
        updateChecker.startMonitoring()
    }

    // MARK: – Update alert

    private func promptForSync(from oldVersion: String, to newVersion: String) {
        guard !isSyncing else { return }

        let installedCount = store.profiles.filter { $0.isDesktopInstalled }.count
        let profileWord = installedCount == 1 ? "profile" : "profiles"

        let alert = NSAlert()
        alert.messageText = "Claude Desktop Updated"
        alert.informativeText = """
            Claude Desktop was updated from v\(oldVersion) to v\(newVersion).

            You have \(installedCount) Desktop \(profileWord) that need to be synced to keep working with the new version.
            """
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill",
                             accessibilityDescription: nil)

        alert.addButton(withTitle: "Sync Now")          // .alertFirstButtonReturn
        alert.addButton(withTitle: "Later")             // .alertSecondButtonReturn
        alert.addButton(withTitle: "Skip This Version") // .alertThirdButtonReturn

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            runSync(newVersion: newVersion)
        case .alertThirdButtonReturn:
            // Mark synced without actually syncing — user explicitly doesn't want it
            updateChecker.markSynced(version: newVersion)
        default:
            break // "Later" — will prompt again next time the app checks
        }
    }

    // MARK: – Sync

    private func runSync(newVersion: String) {
        guard !isSyncing else { return }
        isSyncing = true
        setStatusIcon(syncing: true)

        let cli = store.claudeProfilesBin()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.shell(cli, "sync")

            DispatchQueue.main.async {
                self.isSyncing = false
                self.setStatusIcon(syncing: false)

                if result.status == 0 {
                    self.updateChecker.markSynced(version: newVersion)
                    self.showSyncComplete(version: newVersion)
                } else {
                    self.showSyncError(output: result.output)
                }

                self.store.reload()
                self.buildMenu()
            }
        }
    }

    private func showSyncComplete(version: String) {
        let alert = NSAlert()
        alert.messageText = "Sync Complete"
        alert.informativeText = "All profile app bundles have been updated to Claude v\(version)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showSyncError(output: String) {
        let alert = NSAlert()
        alert.messageText = "Sync Failed"
        alert.informativeText = "An error occurred while syncing profiles.\n\n\(output)\n\nYou can try again manually: claude-profiles sync"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: – Menu

    func buildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Claude Profiles", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        // Show pending update badge if detected
        if let installed = updateChecker.currentInstalledVersion(),
           let synced    = updateChecker.syncedVersion(),
           installed != synced {
            let badge = NSMenuItem(
                title: "⚠️  Claude v\(synced) → v\(installed) — Click to sync",
                action: #selector(manualSync),
                keyEquivalent: ""
            )
            badge.target = self
            menu.addItem(badge)
        }

        menu.addItem(.separator())

        if store.profiles.isEmpty {
            let empty = NSMenuItem(title: "No profiles yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for profile in store.profiles {
                menu.addItem(makeProfileItem(profile))
            }
        }

        menu.addItem(.separator())

        let newItem = NSMenuItem(title: "New Profile…", action: #selector(openNewProfileWindow), keyEquivalent: "n")
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let syncItem = NSMenuItem(
            title: isSyncing ? "Syncing…" : "Sync Profiles",
            action: isSyncing ? nil : #selector(manualSync),
            keyEquivalent: "s"
        )
        syncItem.target = self
        menu.addItem(syncItem)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let manage = NSMenuItem(title: "Open Terminal", action: #selector(openTerminal), keyEquivalent: "t")
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

        let launchDesktop = NSMenuItem(
            title: profile.isDesktopInstalled ? "Launch Desktop" : "Launch Desktop (setup required)",
            action: #selector(launchDesktop(_:)),
            keyEquivalent: ""
        )
        launchDesktop.representedObject = profile.name
        launchDesktop.target = self
        sub.addItem(launchDesktop)

        let launchCode = NSMenuItem(title: "Open Claude Code", action: #selector(launchCode(_:)), keyEquivalent: "")
        launchCode.representedObject = profile.name
        launchCode.target = self
        sub.addItem(launchCode)

        sub.addItem(.separator())

        let setup = NSMenuItem(title: "Setup Desktop Bundle", action: #selector(setupDesktop(_:)), keyEquivalent: "")
        setup.representedObject = profile.name
        setup.target = self
        sub.addItem(setup)

        item.submenu = sub
        return item
    }

    // MARK: – Status icon

    private func setStatusIcon(syncing: Bool) {
        guard let btn = statusItem.button else { return }
        if syncing {
            btn.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                accessibilityDescription: "Syncing profiles…")
        } else {
            btn.image = NSImage(systemSymbolName: "person.3.fill",
                                accessibilityDescription: "Claude Profiles")
        }
    }

    // MARK: – New Profile window

    @objc private func openNewProfileWindow() {
        if let panel = newProfilePanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "New Profile"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let view = NewProfileView(cliPath: store.claudeProfilesBin()) {
            panel.close()
            self.store.reload()
            self.buildMenu()
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        newProfilePanel = panel
    }

    // MARK: – Profile actions

    @objc private func launchDesktop(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        run(store.claudeProfilesBin(), "launch", name)
    }

    @objc private func launchCode(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openTerminalWith("\(store.claudeProfilesBin()) code \(name)")
    }

    @objc private func setupDesktop(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        openTerminalWith("\(store.claudeProfilesBin()) setup \(name) && echo '✓ Done'")
    }

    @objc private func manualSync() {
        guard let installed = updateChecker.currentInstalledVersion() else { return }
        runSync(newVersion: installed)
    }

    @objc private func refresh(_ sender: Any) {
        store.reload()
        buildMenu()
    }

    @objc private func openTerminal(_ sender: Any) {
        openTerminalWith("\(store.claudeProfilesBin()) list")
    }

    // MARK: – Helpers

    private func run(_ args: String...) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = args
        try? task.run()
    }

    private func shell(_ args: String...) -> (output: String, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out.trimmingCharacters(in: .whitespacesAndNewlines), p.terminationStatus)
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
