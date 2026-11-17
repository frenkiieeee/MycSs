import Foundation
import Observation

/// Whether the notch can read the notifications, looked at while the page is open.
@MainActor
@Observable
final class NotificationAccessStatus {
    static let shared = NotificationAccessStatus()
    private(set) var access: NotificationsModel.Access = .unknown
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        check()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let probe = NotificationsModel()
        probe.logsChanges = false
        let result = probe.checkAccess()
        if result != access { access = result }
    }
}
