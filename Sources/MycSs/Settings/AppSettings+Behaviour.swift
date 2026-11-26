import Foundation

/// How the notch reacts to the pointer and to dragged files (spec 013), and what
/// it does with notifications (spec 012). None of these is part of a style.
extension AppSettings {

    // MARK: - Opening and closing

    enum NotchOpenTrigger: String, CaseIterable {
        /// Resting the pointer on it.
        case hover
        /// Only a click.
        case click

        var title: String {
            switch self {
            case .hover: return "Al pasar el puntero"
            case .click: return "Con un clic"
            }
        }
    }

    var notchOpenTrigger: NotchOpenTrigger {
        get { NotchOpenTrigger(rawValue: defaults.string(forKey: SettingKey.notchOpenTrigger) ?? "") ?? .hover }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchOpenTrigger) }
    }

    /// How long the pointer rests on the closed notch before it opens, in seconds.
    var notchOpenDelay: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchOpenDelay) as? Double ?? 0.1, 0, 1) }
        set { defaults.set(Self.clamp(newValue, 0, 1), forKey: SettingKey.notchOpenDelay) }
    }

    /// How long the open notch waits after the pointer leaves, in seconds.
    var notchCloseDelay: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchCloseDelay) as? Double ?? 0.2, 0, 2) }
        set { defaults.set(Self.clamp(newValue, 0, 2), forKey: SettingKey.notchCloseDelay) }
    }

    // MARK: - Dragging files

    /// Whether dragging files onto the closed notch opens the shelf.
    var notchDragOpen: Bool {
        get { defaults.object(forKey: SettingKey.notchDragOpen) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchDragOpen) }
    }

    /// How long files have to be held over the notch before the shelf opens.
    var notchDragDelay: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchDragDelay) as? Double ?? 0.35, 0, 1.5) }
        set { defaults.set(Self.clamp(newValue, 0, 1.5), forKey: SettingKey.notchDragDelay) }
    }

    /// How far around the notch a drag counts.
    enum NotchDragZone: String, CaseIterable {
        case small, normal, large

        var title: String {
            switch self {
            case .small: return "Solo sobre el notch"
            case .normal: return "Normal"
            case .large: return "Amplia"
            }
        }

        /// The margin around the closed notch, in points.
        var padding: CGFloat {
            switch self {
            case .small: return 0
            case .normal: return 10
            case .large: return 36
            }
        }
    }

    var notchDragZone: NotchDragZone {
        get { NotchDragZone(rawValue: defaults.string(forKey: SettingKey.notchDragZone) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchDragZone) }
    }

    // MARK: - Notifications

    /// Where a notification of an app is seen.
    enum NotificationRule: String, CaseIterable, Identifiable {
        /// In the notch, and the system's banner stays.
        case both
        /// In the notch only: the system's banner is closed (needs Accessibility).
        case notch
        /// The system's banner only: MycSs leaves it alone.
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .both: return "Notch y sistema"
            case .notch: return "Solo notch"
            case .system: return "Solo sistema"
            }
        }

        var shownInNotch: Bool { self != .system }
        var hidesBanner: Bool { self == .notch }
    }

    /// The rule of the apps that have none of their own.
    var notchNotificationDefault: NotificationRule {
        get { NotificationRule(rawValue: defaults.string(forKey: SettingKey.notchNotificationDefault) ?? "") ?? .both }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchNotificationDefault) }
    }

    /// The rules the user chose app by app, by bundle identifier.
    var notchNotificationRules: [String: NotificationRule] {
        get {
            let raw = defaults.object(forKey: SettingKey.notchNotificationRules) as? [String: String] ?? [:]
            return raw.compactMapValues(NotificationRule.init(rawValue:))
        }
        set { defaults.set(newValue.mapValues(\.rawValue), forKey: SettingKey.notchNotificationRules) }
    }

    func notificationRule(for bundleID: String) -> NotificationRule {
        notchNotificationRules[bundleID] ?? notchNotificationDefault
    }

    /// Sets an app's rule; the default one is not stored, so changing the default
    /// moves every app that never had its own.
    func setNotificationRule(_ rule: NotificationRule, for bundleID: String) {
        var rules = notchNotificationRules
        rules[bundleID] = rule == notchNotificationDefault ? nil : rule
        notchNotificationRules = rules
    }

    /// How long a notification stays on the closed notch, in seconds.
    var notchNotificationSeconds: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchNotificationSeconds) as? Double ?? 5.5, 2, 12) }
        set { defaults.set(Self.clamp(newValue, 2, 12), forKey: SettingKey.notchNotificationSeconds) }
    }

    /// Whether the text of a notification is shown, or only that one arrived.
    var notchNotificationShowBody: Bool {
        get { defaults.object(forKey: SettingKey.notchNotificationShowBody) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchNotificationShowBody) }
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        value.isFinite ? min(max(value, low), high) : low
    }
}
