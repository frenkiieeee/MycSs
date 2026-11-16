import AppKit
import EventKit
import Observation

/// One reminder, ready to draw.
struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let color: NSColor

    var isOverdue: Bool {
        guard let due else { return false }
        return due < Date()
    }
}

/// The reminders that are not done yet, for the notch.
///
/// Same rules as the calendar: the permission is only asked when the user opens
/// the widget, nothing is read before it, and nothing leaves the Mac. Ticking a
/// reminder in the notch completes it in the Reminders app.
@MainActor
@Observable
final class RemindersModel {

    private(set) var access: AgendaModel.Access = .notAsked
    private(set) var items: [ReminderItem] = []

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let isDemo: Bool

    /// How many fit in the notch.
    static let visibleCount = 3

    init(demo: Bool = CommandLine.arguments.contains("--demo")) {
        isDemo = demo
    }

    private var canUseEventKit: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
    }

    // MARK: - Access

    func prepare() {
        if isDemo {
            access = .granted
            items = Self.demoItems()
            return
        }
        guard canUseEventKit else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            access = .granted
            startObserving()
            refresh(force: true)
        case .notDetermined:
            access = .notAsked
        default:
            access = .denied
        }
    }

    func requestAccess() {
        switch access {
        case .notAsked:
            NSApp.activate(ignoringOtherApps: true)
            let store = EKEventStore()
            self.store = store
            store.requestFullAccessToReminders { [weak self] granted, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.access = granted ? .granted : .denied
                    if granted {
                        self.startObserving()
                        self.refresh(force: true)
                    }
                }
            }
        case .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    // MARK: - Reminders

    func refresh(force: Bool = false) {
        guard access == .granted, !isDemo else { return }
        guard force || Date().timeIntervalSince(lastRefresh) > 15 else { return }
        lastRefresh = Date()

        let store = self.store ?? EKEventStore()
        self.store = store
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            // EventKit's reminders are not `Sendable`: reduce them to plain values
            // before they cross to the main actor.
            let list = (reminders ?? []).map { reminder in
                (
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "Sin título",
                    due: reminder.dueDateComponents?.date,
                    color: reminder.calendar.cgColor.flatMap { NSColor(cgColor: $0) } ?? NSColor.systemOrange
                )
            }
            Task { @MainActor in
                guard let self else { return }
                // What is due soonest first; what has no date last.
                self.items = list
                    .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                    .prefix(30)
                    .map { ReminderItem(id: $0.id, title: $0.title, due: $0.due, color: $0.color) }
            }
        }
    }

    /// Ticks a reminder: it is completed in the Reminders app.
    func complete(_ item: ReminderItem) {
        // The row goes at once; EventKit confirms afterwards.
        items.removeAll { $0.id == item.id }
        guard !isDemo, let store,
              let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder
        else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            Log.warn("reminders: could not complete '\(item.title)': \(error.localizedDescription)")
            refresh(force: true)
        }
    }

    /// Saves a new reminder in the list the Mac uses by default. Returns what went
    /// wrong, or nil when it was saved.
    func createReminder(title: String, due: Date, withTime: Bool) -> String? {
        if isDemo {
            items.append(ReminderItem(id: UUID().uuidString, title: title, due: due, color: .systemPurple))
            return nil
        }
        guard access == .granted else { return "Falta el permiso de recordatorios" }
        let store = self.store ?? EKEventStore()
        self.store = store
        guard let list = store.defaultCalendarForNewReminders() else { return "No hay una lista por defecto" }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        let parts: Set<Calendar.Component> = withTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
        do {
            try store.save(reminder, commit: true)
        } catch {
            Log.warn("reminders: could not save '\(title)': \(error.localizedDescription)")
            return error.localizedDescription
        }
        Log.line("reminders: created '\(title)'")
        refresh(force: true)
        return nil
    }

    private func startObserving() {
        guard observer == nil, let store else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
    }

    private static func demoItems() -> [ReminderItem] {
        let now = Date()
        return [
            ReminderItem(id: "r1", title: "Enviar la factura", due: now.addingTimeInterval(-3600), color: .systemRed),
            ReminderItem(id: "r2", title: "Comprar pan", due: now.addingTimeInterval(2 * 3600), color: .systemOrange),
            ReminderItem(id: "r3", title: "Llamar a Marta", due: nil, color: .systemBlue),
            ReminderItem(id: "r4", title: "Revisar el diseño del notch", due: nil, color: .systemYellow),
        ]
    }
}
