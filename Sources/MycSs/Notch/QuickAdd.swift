import AppKit
import Observation
import SwiftUI

/// What the user is typing in the window that creates an event or a reminder.
@MainActor
@Observable
final class QuickAddModel {

    enum Kind: String, CaseIterable {
        case event, reminder
        var title: String { self == .event ? "Evento" : "Recordatorio" }
    }

    var kind: Kind = .event
    var title = ""
    /// Only the day of this is used.
    var day = Date()
    /// Only the hour and the minutes of this are used.
    var time = Date()
    var allDay = false
    /// For a reminder: with an hour, or only the day.
    var withTime = true
    var minutes = 60
    /// What went wrong, shown in the window.
    var message: String?

    /// The start, from the day and the hour.
    var start: Date {
        let calendar = Calendar.current
        if kind == .event && allDay { return calendar.startOfDay(for: day) }
        if kind == .reminder && !withTime { return calendar.startOfDay(for: day) }
        let hm = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: day) ?? day
    }

    /// The hour that is suggested: the next one on the dot.
    func reset(for day: Date) {
        let calendar = Calendar.current
        title = ""
        message = nil
        kind = .event
        allDay = false
        withTime = true
        minutes = 60
        self.day = day
        let now = Date()
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        time = calendar.date(bySetting: .minute, value: 0, of: nextHour) ?? nextHour
    }

    /// Saves what was typed. Returns whether it worked; if not, `message` says why.
    func save(agenda: AgendaModel, reminders: RemindersModel) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "Escribe un título"
            return false
        }
        let problem: String?
        switch kind {
        case .event:
            problem = agenda.createEvent(
                title: name, start: start, end: start.addingTimeInterval(Double(minutes) * 60), allDay: allDay
            )
            if problem != nil, agenda.access != .granted { agenda.requestAccess() }
        case .reminder:
            problem = reminders.createReminder(title: name, due: start, withTime: withTime)
            if problem != nil, reminders.access != .granted { reminders.requestAccess() }
        }
        message = problem
        return problem == nil
    }
}

/// The small window under the notch where an event or a reminder is written.
///
/// It is a window of its own because the notch is never the key window (so it
/// cannot take the focus from what the user is doing), and a text field needs one.
/// It can take the keyboard without making MycSs the active app.
@MainActor
final class QuickAddController {

    static let shared = QuickAddController()
    let model = QuickAddModel()
    private var panel: QuickAddPanel?
    private var services: NotchServices?

    var isShown: Bool { panel?.isVisible ?? false }

    func present(day: Date, services: NotchServices) {
        self.services = services
        model.reset(for: day)
        if panel == nil {
            let panel = QuickAddPanel()
            panel.onCancel = { [weak self] in self?.close() }
            panel.contentView = NSHostingView(rootView: QuickAddView(
                model: model,
                save: { [weak self] in self?.save() },
                cancel: { [weak self] in self?.close() }
            ))
            self.panel = panel
        }
        guard let panel else { return }
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        Log.line("quick add: shown for \(day.formatted(date: .abbreviated, time: .omitted))")
    }

    func save() {
        guard let services else { return }
        if model.save(agenda: services.agenda, reminders: services.reminders) {
            Log.line("quick add: saved a \(model.kind.rawValue)")
            close()
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    /// Centred under the open notch, on the screen that has it.
    private func position(_ panel: QuickAddPanel) {
        let notch = NSApp.windows.compactMap { $0 as? NotchPanel }.first
        let screen = notch?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = panel.frame.size
        let midX = notch?.frame.midX ?? screen.frame.midX
        let top = (notch?.frame.maxY ?? screen.frame.maxY) - NotchGeometry.openSize.height - 10
        var origin = CGPoint(x: midX - size.width / 2, y: top - size.height)
        origin.x = min(max(origin.x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        origin.y = max(origin.y, screen.frame.minY + 8)
        panel.setFrameOrigin(origin)
    }
}

final class QuickAddPanel: NSPanel {

    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 232),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// A click on another window closes it, like a popover.
    override func resignKey() {
        super.resignKey()
        onCancel?()
    }
}

struct QuickAddView: View {

    @Bindable var model: QuickAddModel
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Tipo", selection: $model.kind) {
                ForEach(QuickAddModel.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(model.kind == .event ? "Título del evento" : "Título del recordatorio", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)

            HStack(spacing: 8) {
                DatePicker("Día", selection: $model.day, displayedComponents: .date)
                    .labelsHidden()
                if showsTime {
                    DatePicker("Hora", selection: $model.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                switch model.kind {
                case .event:
                    Toggle("Todo el día", isOn: $model.allDay)
                    if !model.allDay {
                        Picker("Dura", selection: $model.minutes) {
                            Text("30 min").tag(30)
                            Text("1 h").tag(60)
                            Text("2 h").tag(120)
                            Text("3 h").tag(180)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                case .reminder:
                    Toggle("Con hora", isOn: $model.withTime)
                }
                Spacer(minLength: 0)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            if let message = model.message {
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Crear", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(14)
        .frame(width: 330, height: 232, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }

    private var showsTime: Bool {
        model.kind == .event ? !model.allDay : model.withTime
    }
}
