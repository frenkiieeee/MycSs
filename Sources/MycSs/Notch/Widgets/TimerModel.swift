import AppKit
import Observation

/// A countdown that lives in the notch: pick a time, start it, and it is there on
/// the side of the closed notch until it ends.
@MainActor
@Observable
final class TimerModel {

    enum State: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    /// The times on offer, in minutes.
    static let presets = [5, 10, 25, 50]

    private(set) var state: State = .idle
    /// The length of the countdown that is set, in seconds.
    private(set) var total: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60

    /// The time the ruler is on, in minutes (spec 016).
    var rulerMinutes = 25
    @ObservationIgnored var rulerDragStart: Int?

    /// Called once when the countdown reaches zero.
    @ObservationIgnored var onFinish: (() -> Void)?

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?

    /// 0 to 1, how much has gone by.
    var progress: Double {
        total > 0 ? min(max(1 - remaining / total, 0), 1) : 0
    }

    /// Whether it should show in the closed notch.
    var isActive: Bool { state == .running || state == .paused }

    /// `mm:ss`, or `h:mm:ss`.
    var text: String { Self.format(remaining) }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Control

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        remaining = total
        resume()
    }

    func toggle() {
        switch state {
        case .running: pause()
        case .paused: resume()
        case .idle, .finished: start(minutes: Int(total / 60))
        }
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        state = .idle
        remaining = total
    }

    private func resume() {
        endDate = Date().addingTimeInterval(remaining)
        state = .running
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func pause() {
        guard state == .running else { return }
        tick()
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        state = .paused
    }

    private func tick() {
        guard state == .running, let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        state = .finished
        remaining = 0
        NSSound(named: "Glass")?.play()
        onFinish?()
    }
}
