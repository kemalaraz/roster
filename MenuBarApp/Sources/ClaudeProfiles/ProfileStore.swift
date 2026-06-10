import Foundation

final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = []

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-profiles/profiles.json")
    }

    init() { reload() }

    func reload() {
        guard
            let data   = try? Data(contentsOf: configURL),
            let config = try? JSONDecoder().decode(ProfilesConfig.self, from: data)
        else {
            profiles = []
            return
        }
        profiles = config.profiles
    }

    /// Resolves the claude-profiles CLI path.
    /// Prefers the copy bundled inside the .app (Resources/bin/), then falls
    /// back to common system-wide install locations.
    func claudeProfilesBin() -> String {
        // 1. Bundled inside .app — works with no system install required
        if let bundled = Bundle.main.path(forResource: "claude-profiles", ofType: nil, inDirectory: "bin") {
            return bundled
        }

        // 2. System install locations
        let candidates = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude-profiles",
            "/opt/homebrew/bin/claude-profiles",
            "/usr/local/bin/claude-profiles",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "claude-profiles"
    }
}
