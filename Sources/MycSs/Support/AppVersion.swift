import Foundation

/// The version of the app, from the bundle's `Info.plist` (which `build-app.sh`
/// fills from the `VERSION` file). A binary built with plain `swift build` has no
/// `Info.plist` and reports `dev`.
enum AppVersion {

    /// Semantic version, for example `0.2.5`.
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// The build number (the commit count when it was built).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// `0.2.5 (build 42)`.
    static var display: String { short == "dev" ? "dev" : "\(short) (build \(build))" }

    /// Where the project lives.
    static let repository = "https://github.com/frenkiieeee/MycSs"

    /// A parsed semantic version, to compare with the latest release.
    struct Semantic: Comparable {
        let major: Int, minor: Int, patch: Int

        init?(_ text: String) {
            let core = text.trimmingCharacters(in: .whitespaces)
                .drop { $0 == "v" || $0 == "V" }
                .split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
            let parts = core.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            (major, minor, patch) = (parts[0], parts[1], parts[2])
        }

        static func < (a: Semantic, b: Semantic) -> Bool {
            (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
    }
}
