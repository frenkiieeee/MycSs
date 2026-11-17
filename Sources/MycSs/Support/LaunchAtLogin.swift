import Foundation
import Observation
import ServiceManagement

/// Starts MycSs when the user logs in, using the system's own login items
/// (`SMAppService`), so there is nothing to install and the user can also see and
/// remove it in System Settings > General > Login Items.
///
/// It only works from an app in `/Applications` (or `~/Applications`); a copy that
/// runs from the build folder says so instead of failing silently.
@MainActor
@Observable
final class LaunchAtLogin {

    static let shared = LaunchAtLogin()

    private(set) var isEnabled = false
    /// Why it cannot be turned on, or what went wrong.
    private(set) var message: String?

    private init() { refresh() }

    /// Whether this build is a real app bundle, which is what the service needs.
    var isAvailable: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    func refresh() {
        guard isAvailable else {
            isEnabled = false
            message = "Solo funciona con MycSs.app (no con el binario de swift build)."
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            message = nil
        case .requiresApproval:
            isEnabled = false
            message = "Falta aprobarlo en Ajustes del Sistema > General > Ítems de inicio."
        case .notFound:
            isEnabled = false
            message = "macOS no encuentra la app: muévela a Aplicaciones."
        default:
            isEnabled = false
            message = nil
        }
    }

    func set(_ enabled: Bool) {
        guard isAvailable else { return refresh() }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.line("login item: \(enabled ? "registered" : "removed")")
        } catch {
            Log.warn("login item: \(error.localizedDescription)")
            message = error.localizedDescription
        }
        refresh()
    }
}
