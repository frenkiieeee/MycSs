import AppKit
import Observation
import SwiftUI

/// The pages of the open notch.
enum NotchTab: String {
    /// Music on the left, the calendar on the right.
    case home
    /// A shelf for files, with AirDrop.
    case shelf
}

/// The springs of the notch. One for opening, one for closing, one for the small
/// changes inside it; nothing in the notch animates with anything else. The feel
/// is the user's: smooth, bouncy, snappy or slow.
enum NotchMotion {

    private static var style: AppSettings.NotchMotionStyle { AppSettings.shared.notchMotion }

    static var open: Animation {
        switch style {
        case .smooth: return .spring(response: 0.40, dampingFraction: 0.78)
        case .bouncy: return .spring(response: 0.46, dampingFraction: 0.58)
        case .snappy: return .spring(response: 0.26, dampingFraction: 0.86)
        case .slow: return .spring(response: 0.72, dampingFraction: 0.92)
        }
    }

    static var close: Animation {
        switch style {
        case .smooth: return .spring(response: 0.36, dampingFraction: 0.94)
        case .bouncy: return .spring(response: 0.40, dampingFraction: 0.78)
        case .snappy: return .spring(response: 0.24, dampingFraction: 0.96)
        case .slow: return .spring(response: 0.60, dampingFraction: 1.0)
        }
    }

    /// The small changes inside: a tab, a day, a state.
    static var swap: Animation {
        switch style {
        case .smooth: return .smooth(duration: 0.28)
        case .bouncy: return .spring(response: 0.34, dampingFraction: 0.66)
        case .snappy: return .smooth(duration: 0.16)
        case .slow: return .smooth(duration: 0.45)
        }
    }

    /// The notch widening and narrowing for a new song: a spring whose length the
    /// user sets, with a little overshoot that depends on the movement style.
    static var peek: Animation {
        let bounce: Double
        switch style {
        case .smooth: bounce = 0.18
        case .bouncy: bounce = 0.4
        case .snappy: bounce = 0.0
        case .slow: bounce = 0.05
        }
        return .spring(duration: AppSettings.shared.notchPeekDuration, bounce: bounce)
    }

    /// How the indicator comes in. The notch widens with it.
    static var hudIn: Animation {
        switch AppSettings.shared.notchHUDEntrance {
        case .grow: return .spring(response: 0.36, dampingFraction: 0.8)
        case .pop: return .spring(response: 0.42, dampingFraction: 0.5)
        case .slide: return .smooth(duration: 0.34)
        case .fade: return .easeOut(duration: 0.2)
        }
    }

    /// How it goes.
    static var hudOut: Animation {
        switch AppSettings.shared.notchHUDEntrance {
        case .grow, .slide: return .spring(response: 0.34, dampingFraction: 0.92)
        case .pop: return .spring(response: 0.3, dampingFraction: 0.85)
        case .fade: return .easeIn(duration: 0.2)
        }
    }

    /// How the value travels from one position to the next. A spring, so a quick
    /// second press carries on from where the first one was instead of starting over.
    static var hudValue: Animation {
        switch AppSettings.shared.notchHUDMotion {
        case .smooth: return .interpolatingSpring(stiffness: 190, damping: 24)
        case .elastic: return .spring(response: 0.5, dampingFraction: 0.5)
        case .glide: return .easeOut(duration: 0.55)
        }
    }

    /// The delay between the width and the height when it opens to the sides first.
    static var heightDelay: Double {
        switch style {
        case .smooth: return 0.09
        case .bouncy: return 0.11
        case .snappy: return 0.05
        case .slow: return 0.18
        }
    }
}

/// The state of the notch, and the only place that changes it.
///
/// The view reports the hover and the clicks; the controller reports the song,
/// the keys and the pointer; everything ends up in `open`, `close`, `peek` and
/// `showHUD`, so there is one path for each thing the notch can do.
@MainActor
@Observable
final class NotchModel {

    private(set) var isOpen = false
    var tab: NotchTab = .home
    /// A few seconds wider, with the title and the artist, when the song changes.
    private(set) var isPeeking = false {
        didSet { if oldValue, !isPeeking { peekEndedAt = Date() } }
    }
    @ObservationIgnored private var peekEndedAt = Date.distantPast
    /// True for a moment after the title goes, so the narrowing is animated like the widening.
    var peekClosing: Bool { Date().timeIntervalSince(peekEndedAt) < 1.5 }
    /// The volume or the brightness, for a moment after it changes.
    private(set) var hud: NotchHUD?
    /// What the indicator draws: it travels to the real value with an animation, so
    /// the bar, the ring and the number glide instead of jumping.
    private(set) var hudShown: CGFloat = 0
    @ObservationIgnored private var lastHUDValue: [NotchHUD.Kind: CGFloat] = [:]
    /// Whether files are being dragged over the shelf.
    var shelfTargeted = false

    /// A notification of another app, for a few seconds.
    private(set) var notification: NotchNotification?
    @ObservationIgnored private var notificationTask: Task<Void, Never>?

    /// The widget showing on the right of the home page.
    var widget: AppSettings.NotchWidget = AppSettings.shared.notchWidgetSelected {
        didSet { AppSettings.shared.notchWidgetSelected = widget }
    }

    /// Whether music is playing, or just stopped. Only then does the closed notch
    /// grow its sides and show the title; otherwise it folds back into the
    /// hardware notch and nothing of it shows. The controller decides it.
    var isListening = false

    /// Whether the pointer is really inside the notch right now, by position.
    /// The controller sets it. It guards the close: a hover that ends while the
    /// shape is still animating must not close the notch under the pointer.
    @ObservationIgnored var isPointerInside: () -> Bool = { false }

    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?

    /// With more than one screen, the one where the pointer is (set before it opens) and
    /// the one where it opened. 0 is "the main one". The notch opens only on that screen.
    var hoverDisplay: CGDirectDisplayID = 0
    private(set) var openDisplay: CGDirectDisplayID = 0

    /// How long the pointer has to rest on the notch before it opens, so that
    /// crossing the top of the screen does not open it.
    private let openDelay: UInt64 = 90_000_000
    private let closeDelay: UInt64 = 180_000_000

    // MARK: - Hover

    /// The hover of the notch's own shape.
    func hover(_ inside: Bool, display: CGDirectDisplayID = 0) {
        hoverTask?.cancel()
        isHovering = inside
        if inside { hoverDisplay = display }

        if inside {
            guard !isOpen else { return }
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: openDelay)
                guard !Task.isCancelled, isHovering, !isOpen else { return }
                open(haptic: true)
            }
        } else {
            guard isOpen else { return }
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: closeDelay)
                guard !Task.isCancelled, !isHovering, !shelfTargeted, !isPointerInside() else { return }
                close("the pointer left")
            }
        }
    }

    // MARK: - Open and close

    func open(tab: NotchTab? = nil, haptic: Bool = false) {
        if let tab { self.tab = tab }
        guard !isOpen else { return }
        openDisplay = hoverDisplay
        isOpen = true
        isPeeking = false
        peekTask?.cancel()
        if haptic {
            // The small tick of the trackpad, like the system's own controls.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        Log.line("notch: opened")
    }

    func close(_ reason: String = "closed") {
        guard isOpen else { return }
        hoverTask?.cancel()
        isOpen = false
        Log.line("notch: closed (\(reason))")
    }

    // MARK: - Peek

    /// Shows the title and the artist for a few seconds.
    func peek(for seconds: TimeInterval = AppSettings.shared.notchPeekSeconds) {
        guard !isOpen else { return }
        isPeeking = true
        peekTask?.cancel()
        peekTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            isPeeking = false
        }
    }

    // MARK: - Volume and brightness

    func showHUD(_ hud: NotchHUD, for seconds: TimeInterval = 1.6) {
        let target = hud.shownValue
        let appearing = self.hud == nil
        // The indicator appears where the value was and then travels to the new
        // one, so the change is seen as movement.
        let start = appearing ? (lastHUDValue[hud.kind] ?? target) : hudShown
        lastHUDValue[hud.kind] = target

        // The indicator takes the place of the peek.
        if !isOpen {
            isPeeking = false
            peekTask?.cancel()
        }

        if appearing {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { hudShown = start }
            withAnimation(NotchMotion.hudIn) { self.hud = hud }
        } else {
            self.hud = hud
        }
        if start != target {
            // One tick later, so the first frame is drawn at the old value.
            DispatchQueue.main.async { [weak self] in
                withAnimation(NotchMotion.hudValue) { self?.hudShown = target }
            }
        } else {
            hudShown = target
        }

        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(NotchMotion.hudOut) { self.hud = nil }
        }
    }

    // MARK: - Notifications

    /// Shows a notification, for a few seconds. Pointing at it keeps it.
    func showNotification(_ notification: NotchNotification, for seconds: TimeInterval = 5.5) {
        self.notification = notification
        isPeeking = false
        peekTask?.cancel()
        notificationTask?.cancel()
        notificationTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.notification = nil
        }
        Log.line("notch: notification from \(notification.appName)")
    }

    func dismissNotification() {
        notificationTask?.cancel()
        notification = nil
    }

    /// Back to the idle state, when the notch leaves the screen.
    func reset() {
        hoverTask?.cancel()
        peekTask?.cancel()
        hudTask?.cancel()
        notificationTask?.cancel()
        isOpen = false
        isPeeking = false
        hud = nil
        hudShown = 0
        notification = nil
        isHovering = false
        shelfTargeted = false
        isListening = false
    }
}
