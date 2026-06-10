import Foundation
import AppKit

// Persisted in ~/.claude-profiles/claude-version.json
// Written by both this app and the Python CLI after a successful sync.
private struct VersionRecord: Codable {
    var syncedVersion: String
    var lastSynced: Date

    enum CodingKeys: String, CodingKey {
        case syncedVersion = "synced_version"
        case lastSynced    = "last_synced"
    }
}

final class UpdateChecker {

    // MARK: – Config

    static let claudeAppPath  = "/Applications/Claude.app"
    static let claudePlistPath = claudeAppPath + "/Contents/Info.plist"

    private static var versionFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-profiles/claude-version.json")
    }

    // Called on main thread when current ≠ synced version.
    // Args: (syncedVersion, installedVersion)
    var onUpdateDetected: ((String, String) -> Void)?

    // MARK: – Private state

    private var fsSource: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var lastReportedPair: (String, String)?   // avoid double-alerting

    // MARK: – Public API

    func startMonitoring() {
        checkNow()
        watchApplicationsFolder()
        schedulePeriodicCheck()
    }

    func stopMonitoring() {
        fsSource?.cancel()
        fsSource = nil
        timer?.invalidate()
        timer = nil
    }

    /// Called after a successful sync (by app or CLI via shared JSON file).
    func markSynced(version: String) {
        let record = VersionRecord(syncedVersion: version, lastSynced: Date())
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: Self.versionFileURL, options: .atomic)
        lastReportedPair = nil   // reset so a future real update shows the alert again
    }

    func currentInstalledVersion() -> String? {
        guard let plist = NSDictionary(contentsOfFile: Self.claudePlistPath) else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    func syncedVersion() -> String? {
        guard
            let data   = try? Data(contentsOf: Self.versionFileURL),
            let record = try? JSONDecoder().decode(VersionRecord.self, from: data)
        else { return nil }
        return record.syncedVersion
    }

    // MARK: – Check logic

    func checkNow() {
        guard let installed = currentInstalledVersion() else { return }

        guard let synced = syncedVersion() else {
            // First run — record current version silently; no profiles synced yet so nothing is stale.
            markSynced(version: installed)
            return
        }

        guard synced != installed else { return }

        // Avoid firing the callback twice for the same (old, new) pair
        if let last = lastReportedPair, last == (synced, installed) { return }
        lastReportedPair = (synced, installed)

        DispatchQueue.main.async { [weak self] in
            self?.onUpdateDetected?(synced, installed)
        }
    }

    // MARK: – File-system watcher

    /// Watch /Applications/ — Claude's Sparkle updater replaces the whole .app
    /// bundle, which triggers a write event on the parent directory.
    private func watchApplicationsFolder() {
        let fd = open("/Applications", O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        source.setEventHandler { [weak self] in
            // Small debounce — Sparkle does several writes in quick succession
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.checkNow()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fsSource = source
    }

    // MARK: – Periodic timer (belt-and-suspenders)

    private func schedulePeriodicCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
    }
}
