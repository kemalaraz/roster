import Foundation

struct Profile: Codable, Identifiable {
    var id: String { name }
    let name: String
    let displayName: String
    let color: String
    let emoji: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case color
        case emoji
        case createdAt  = "created_at"
    }

    var slug: String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    var appPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude-\(slug).app")
    }

    var codeConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-profiles/\(slug)/claude-code")
    }

    var isDesktopInstalled: Bool {
        FileManager.default.fileExists(atPath: appPath.path)
    }
}

struct ProfilesConfig: Codable {
    let profiles: [Profile]
}
