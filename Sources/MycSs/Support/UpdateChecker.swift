import AppKit
import Foundation
import Observation

/// Asks GitHub whether there is a newer release. It only runs when the user
/// presses the button in About: nothing is checked in the background, and the
/// request carries nothing about the user or the Mac.
@MainActor
@Observable
final class UpdateChecker {

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    static let shared = UpdateChecker()
    private(set) var state: State = .idle

    private let endpoint = URL(string: "https://api.github.com/repos/frenkiieeee/MycSs/releases/latest")!

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: endpoint, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // A generic client name, nothing else.
        request.setValue("MycSs-update-check", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)

        Task {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 404 {
                    state = .upToDate
                    return
                }
                guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
                state = Self.interpret(data)
            } catch {
                state = .failed("No se pudo comprobar: \(error.localizedDescription)")
            }
        }
    }

    /// Reads the release and compares it with the running version.
    nonisolated static func interpret(_ data: Data, current: String = AppVersion.short) -> State {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let latest = AppVersion.Semantic(tag)
        else { return .failed("La respuesta de GitHub no se entiende.") }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: AppVersion.repository + "/releases/latest")!
        guard let mine = AppVersion.Semantic(current) else { return .available(version: tag, url: page) }
        return latest > mine ? .available(version: tag, url: page) : .upToDate
    }
}
