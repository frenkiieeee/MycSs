import AppKit
import EventKit
import Observation

/// One event of the agenda, ready to draw.
struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let calendar: String
}

/// The next events of the user's calendars, for the notch.
///
/// It reads them with EventKit, which asks for the Calendar permission the first
/// time the user opens the calendar tab (never before). Nothing is read until
/// that permission is granted, and nothing leaves the Mac.
@MainActor
@Observable
final class AgendaModel {

    enum Access {
        /// The user has not been asked yet.
        case notAsked
        case granted
        case denied
        /// This build cannot use the calendar (see `canUseEventKit`).
        case unavailable
    }

    private(set) var access: Access = .notAsked
    private(set) var events: [AgendaEvent] = []

    /// How many days each side of the selected one the strip shows.
    static let visibleSide = 3
    /// How far back and forward the user can go, and so how far events are read.
    static let fetchBefore = 14
    static let fetchAfter = 45

    /// The day selected in the strip, as an offset from today (0 is today). The
    /// strip is always centred on it.
    private(set) var selectedOffset = 0

    /// Selects a day, within the range that is read. Returns whether it changed.
    @discardableResult
    func select(_ offset: Int) -> Bool {
        let clamped = min(max(offset, -Self.fetchBefore), Self.fetchAfter)
        guard clamped != selectedOffset else { return false }
        selectedOffset = clamped
        return true
    }

    /// The date of an offset from today.
    static func date(forOffset offset: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    /// The events of the selected day. Today hides what is already over; the
    /// other days show everything.
    var eventsForSelectedDay: [AgendaEvent] {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: selectedOffset, to: calendar.startOfDay(for: Date()))
        else { return [] }
        let now = Date()
        return events.filter { event in
            let onThatDay = calendar.isDate(event.start, inSameDayAs: day)
                || (event.start < day && event.end > day)
            guard onThatDay else { return false }
            return selectedOffset != 0 || event.isAllDay || event.end > now
        }
    }

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let isDemo: Bool

    init(demo: Bool = DemoFlags.isDemo) {
        isDemo = demo
    }

    /// How many events fit under the strip.
    static let visibleCount = 2

    /// EventKit ends the app if it is used without the usage description in the
    /// `Info.plist`, and a plain `swift build` binary has no `Info.plist`. So the
    /// calendar is only used from the packaged app.
    private var canUseEventKit: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    // MARK: - Access

    /// Reads the state of the permission **without asking**.
    func prepare() {
        if isDemo {
            access = .granted
            events = Self.demoEvents()
            return
        }
        guard canUseEventKit else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
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

    /// Asks for the permission, or opens the system settings when it was refused.
    func requestAccess() {
        switch access {
        case .notAsked:
            // An app without a Dock icon has to come forward first, or the
            // system's permission dialog can fail to appear.
            NSApp.activate(ignoringOtherApps: true)
            let store = EKEventStore()
            self.store = store
            store.requestFullAccessToEvents { [weak self] granted, _ in
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
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    // MARK: - Events

    /// Reads the events again, at most every twenty seconds unless forced.
    func refresh(force: Bool = false) {
        guard access == .granted, !isDemo else { return }
        guard force || Date().timeIntervalSince(lastRefresh) > 20 else { return }
        lastRefresh = Date()

        let store = self.store ?? EKEventStore()
        self.store = store

        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -Self.fetchBefore, to: today),
              let end = calendar.date(byAdding: .day, value: Self.fetchAfter + 1, to: today)
        else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { ($0.startDate, $0.isAllDay ? 0 : 1) < ($1.startDate, $1.isAllDay ? 0 : 1) }
            .prefix(400)
            .map { event in
                AgendaEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Sin título",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.cgColor.flatMap { NSColor(cgColor: $0) } ?? .systemBlue,
                    calendar: event.calendar.title
                )
            }
    }

    /// Saves a new event in the calendar the Mac uses by default. Returns what went
    /// wrong, or nil when it was saved.
    func createEvent(title: String, start: Date, end: Date, allDay: Bool) -> String? {
        if isDemo {
            events.append(AgendaEvent(
                id: UUID().uuidString, title: title, start: start, end: end,
                isAllDay: allDay, color: .systemPurple, calendar: "Demo"
            ))
            events.sort { $0.start < $1.start }
            return nil
        }
        guard access == .granted else { return "Falta el permiso del calendario" }
        let store = self.store ?? EKEventStore()
        self.store = store
        guard let calendar = store.defaultCalendarForNewEvents else { return "No hay un calendario por defecto" }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = allDay ? start : max(end, start.addingTimeInterval(60))
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            Log.warn("calendar: could not save '\(title)': \(error.localizedDescription)")
            return error.localizedDescription
        }
        Log.line("calendar: created '\(title)'")
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

    // MARK: - Demo

    private static func demoEvents() -> [AgendaEvent] {
        let now = Date()
        let calendar = Calendar.current
        func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return [
            AgendaEvent(id: "1", title: "Revisión de diseño", start: at(25), end: at(70),
                        isAllDay: false, color: .systemOrange, calendar: "Trabajo"),
            AgendaEvent(id: "2", title: "Comida con Marta", start: at(190), end: at(260),
                        isAllDay: false, color: .systemTeal, calendar: "Personal"),
            AgendaEvent(id: "3", title: "Entrega de MycSs", start: tomorrow.addingTimeInterval(11 * 3600),
                        end: tomorrow.addingTimeInterval(12 * 3600),
                        isAllDay: false, color: .systemYellow, calendar: "Proyectos"),
        ]
    }
}
