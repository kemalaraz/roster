// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeProfiles",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeProfiles",
            path: "Sources/ClaudeProfiles",
            swiftSettings: [
                // Use Swift 5 language mode to avoid Swift 6 strict concurrency
                // errors in AppKit/NSApplication code. Upgrade incrementally.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
