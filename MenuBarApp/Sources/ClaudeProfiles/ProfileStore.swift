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

    func claudeProfilesBin() -> String {
        // Look for the CLI on common paths
        let candidates = [
            "/usr/local/bin/claude-profiles",
            "/opt/homebrew/bin/claude-profiles",
            (FileManager.default.homeDirectoryForCurrentUser.path) + "/.local/bin/claude-profiles",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "claude-profiles"
    }
}
