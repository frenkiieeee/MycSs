// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MycSs",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MycSs",
            path: "Sources/MycSs",
            // Swift 5 language mode: the AppKit/SkyLight code uses C callbacks and
            // main-thread window work that Swift 6's strict concurrency checker
            // rejects. Revisit if/when the code is restructured around actors.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
