import SwiftUI

// MARK: - The widget block

/// The right side of the home page: one widget at a time, with a row of small
/// icons in its header to change between the ones the user turned on.
struct WidgetBlock: View {

    @Bindable var notch: NotchModel
    let services: NotchServices

    var body: some View {
        let enabled = AppSettings.shared.notchWidgets
        let current = enabled.contains(notch.widget) ? notch.widget : (enabled.first ?? .calendar)

        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(current: current, enabled: enabled, notch: notch, services: services)

            Group {
                switch current {
                case .calendar: CalendarWidget(agenda: services.agenda)
                case .reminders: RemindersWidget(reminders: services.reminders)
                case .timer: TimerWidget(timer: services.timer)
                case .system: SystemWidget(system: services.system)
                case .clipboard: ClipboardWidget(clipboard: services.clipboard)
                case .notifications: NotificationsWidget(notifications: services.notifications)
                }
            }
            .id(current)
            .transition(.blurReplace)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(NotchMotion.swap, value: current)
    }
}

/// The title of the widget, and the icons that switch between widgets.
private struct WidgetHeader: View {

    let current: AppSettings.NotchWidget
    let enabled: [AppSettings.NotchWidget]
    @Bindable var notch: NotchModel
    let services: NotchServices

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)

            if enabled.count > 1 {
                HStack(spacing: 0) {
                    ForEach(enabled) { widget in
                        let active = widget == current
                        Button {
                            notch.widget = widget
                            NotchHaptics.tick()
                        } label: {
                            Image(systemName: widget.symbol)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(active ? 0.95 : 0.35))
                                .frame(width: 22, height: 22)
                                .background {
                                    if active { Circle().fill(.white.opacity(0.16)) }
                                }
                        }
                        .buttonStyle(NotchPress(scale: 0.88))
                        .probe("widget.\(widget.rawValue)")
                    }
                }
                .animation(NotchMotion.swap, value: current)
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        switch current {
        case .calendar:
            let selected = AgendaModel.date(forOffset: services.agenda.selectedOffset)
            // Pressing the date writes a new event or reminder for that day.
            Button {
                QuickAddController.shared.present(day: selected, services: services)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(selected.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(selected.formatted(.dateTime.year()))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .contentTransition(.numericText())
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(brandYellow.opacity(0.85))
                }
            }
            .buttonStyle(NotchPress(scale: 0.94))
            .probe("calendarTitle")
            .animation(NotchMotion.swap, value: services.agenda.selectedOffset)
        case .notifications:
            HStack(spacing: 6) {
                Text("Avisos")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if services.notifications.history.count > 1 {
                    Text("\(services.notifications.history.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(brandYellow))
                        .contentTransition(.numericText())
                }
                if !services.notifications.history.isEmpty {
                    Button {
                        services.notifications.clearHistory()
                        NotchHaptics.tick()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(NotchPress(scale: 0.88))
                    .help("Borrar el historial")
                    .probe("notification.clear")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(NotchMotion.swap, value: services.notifications.history.isEmpty)
            .animation(NotchMotion.swap, value: services.notifications.history.count)
        case .clipboard:
            HStack(spacing: 6) {
                Text("Copiado")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !services.clipboard.entries.isEmpty {
                    Button {
                        services.clipboard.clear()
                        NotchHaptics.tick()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(NotchPress(scale: 0.88))
                    .help("Limpiar el portapapeles guardado")
                    .probe("clipboard.clear")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(NotchMotion.swap, value: services.clipboard.entries.isEmpty)
        default:
            Text(current.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

/// What a widget shows when it needs a permission.
private struct PermissionPrompt: View {
    let text: String
    let symbol: String
    let probeID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(text)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(NotchPress(scale: 0.94))
        .probe(probeID)
        .padding(.top, 8)
    }
}

private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

// MARK: - Calendar

/// The week, and the events of the day that is selected.
private struct CalendarWidget: View {

    @Bindable var agenda: AgendaModel
    /// The scroll travelled and not yet turned into a day. A class, because
    /// `@State` is not available in this build.
    private let scroll = ScrollAccumulator()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WeekStrip(agenda: agenda)
            events
        }
        // Two fingers to the sides move through the days. (Left out of captures: the
        // renderer draws a warning square over a view of this kind.)
        .overlay {
            if !NotchSnapshot.isActive {
                ScrollCatcher { delta, began in
                    move(by: delta, began: began)
                }
            }
        }
        .probe("calendar")
    }

    /// Turns the travel of the fingers into days, with a tick of the trackpad for
    /// each one.
    private func move(by delta: CGFloat, began: Bool) {
        if began { scroll.rest = 0 }
        scroll.rest += delta
        let step: CGFloat = 26
        let days = Int(scroll.rest / step)
        guard days != 0 else { return }
        scroll.rest -= CGFloat(days) * step
        // Fingers to the right bring the earlier days.
        if agenda.select(agenda.selectedOffset - days) {
            NotchHaptics.tick()
        }
    }

    @ViewBuilder
    private var events: some View {
        switch agenda.access {
        case .granted:
            let list = agenda.eventsForSelectedDay
            Group {
                if list.isEmpty {
                    EmptyNote(text: "Sin eventos")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(list.prefix(AgendaModel.visibleCount)) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .id(agenda.selectedOffset)
            .transition(.blurReplace)
            .animation(NotchMotion.swap, value: agenda.selectedOffset)
        case .notAsked:
            PermissionPrompt(text: "Permitir el calendario", symbol: "calendar.badge.plus", probeID: "calendarAccess") {
                agenda.requestAccess()
            }
        case .denied:
            PermissionPrompt(text: "Activar en Ajustes", symbol: "lock.fill", probeID: "calendarAccess") {
                agenda.requestAccess()
            }
        case .unavailable:
            EmptyNote(text: "Solo desde MycSs.app")
        }
    }
}

/// The scroll that has not yet become a day.
private final class ScrollAccumulator {
    var rest: CGFloat = 0
}

/// The small tick of the trackpad.
enum NotchHaptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// The days, in one long row that slides under a window seven days wide, so a
/// change of day is a movement and not a swap. The selected day is always in the
/// middle; the ends fade out.
///
/// **The days are not buttons.** The row is sixty days long and only seven show;
/// clipping hides the rest, but SwiftUI still delivered clicks to the hidden
/// buttons, which sit over the music, so a click on the seek bar picked a day. The
/// row ignores hits altogether, and one tap gesture on the window of seven days
/// works out which day was pressed from where.
private struct WeekStrip: View {

    @Bindable var agenda: AgendaModel

    private var cell: CGFloat { HomeLayout.widgetWidth / CGFloat(AgendaModel.visibleSide * 2 + 1) }
    private var visible: CGFloat { CGFloat(AgendaModel.visibleSide * 2 + 1) }

    var body: some View {
        let calendar = Calendar.current
        let cell = self.cell
        let range = Array(-AgendaModel.fetchBefore...AgendaModel.fetchAfter)
        // Where the row starts so the selected day is the fourth of seven.
        let shift = -CGFloat(agenda.selectedOffset + AgendaModel.fetchBefore - AgendaModel.visibleSide) * cell

        HStack(spacing: 0) {
            ForEach(range, id: \.self) { offset in
                let day = AgendaModel.date(forOffset: offset)
                let selected = offset == agenda.selectedOffset
                let isToday = offset == 0
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(selected ? 0.9 : 0.4))
                    ZStack {
                        if selected {
                            Circle().fill(brandYellow)
                        } else if isToday {
                            Circle().strokeBorder(brandYellow.opacity(0.8), lineWidth: 1.5)
                        }
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? Color.black.opacity(0.88) : .white.opacity(0.9))
                    }
                    .frame(width: 24, height: 24)
                }
                .frame(width: cell, height: 38)
            }
        }
        .offset(x: shift)
        .frame(width: cell * visible, alignment: .leading)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: agenda.selectedOffset)
        // Nothing in the long row takes a hit.
        .allowsHitTesting(false)
        // One gesture on the seven days that show.
        .overlay {
            Color.clear
                .frame(width: cell * visible, height: 38)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { tap in
                        let slot = Int(tap.location.x / cell) - AgendaModel.visibleSide
                        if agenda.select(agenda.selectedOffset + slot) { NotchHaptics.tick() }
                    }
                )
        }
        .frame(width: cell * visible, height: 38)
        .probe("strip")
    }
}

/// One event, on one line: its calendar's colour, its title, and its hours.
private struct EventRow: View {

    let event: AgendaEvent

    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 3.5, height: 20)
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if event.isAllDay {
                Text("Todo el día")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("\(event.start.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(isNow ? brandYellow : .white.opacity(0.85))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
        .frame(height: 22)
    }

    /// The event that is happening now has its start time in yellow.
    private var isNow: Bool {
        let now = Date()
        return event.start <= now && event.end > now
    }
}

// MARK: - Reminders

/// What is left to do. A tick on the circle completes it in Reminders.
private struct RemindersWidget: View {

    @Bindable var reminders: RemindersModel

    var body: some View {
        content
            .onAppear {
                reminders.prepare()
                reminders.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch reminders.access {
        case .granted:
            if reminders.items.isEmpty {
                EmptyNote(text: "Todo hecho. Nada pendiente")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(reminders.items.prefix(RemindersModel.visibleCount).enumerated()), id: \.element.id) { index, item in
                        row(item, index: index)
                    }
                }
                .animation(NotchMotion.swap, value: reminders.items)
                .padding(.top, 2)
            }
        case .notAsked:
            PermissionPrompt(text: "Permitir recordatorios", symbol: "checklist", probeID: "remindersAccess") {
                reminders.requestAccess()
            }
        case .denied:
            PermissionPrompt(text: "Activar en Ajustes", symbol: "lock.fill", probeID: "remindersAccess") {
                reminders.requestAccess()
            }
        case .unavailable:
            EmptyNote(text: "Solo desde MycSs.app")
        }
    }

    private func row(_ item: ReminderItem, index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(NotchMotion.swap) { reminders.complete(item) }
                NotchHaptics.tick()
            } label: {
                Circle()
                    .strokeBorder(Color(nsColor: item.color), lineWidth: 1.7)
                    .frame(width: 17, height: 17)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(NotchPress(scale: 0.8))
            .probe("reminder.\(index)")

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = item.due {
                Text(due.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(item.isOverdue ? Color(red: 1, green: 0.42, blue: 0.38) : .white.opacity(0.5))
            }
        }
        .frame(height: 28)
        .transition(.blurReplace.combined(with: .opacity))
    }
}

// MARK: - Timer

/// A countdown. Pick a time and it runs; it shows beside the closed notch.
private struct TimerWidget: View {

    @Bindable var timer: TimerModel
    /// The style of the timer is a setting: reading this redraws the widget when it changes.
    @Bindable var revision = SettingsRevision.shared

    var body: some View {
        let _ = revision.value
        Group {
            if timer.isActive || timer.state == .finished {
                running
            } else {
                presets
            }
        }
        .animation(NotchMotion.swap, value: timer.state)
    }

    @ViewBuilder
    private var presets: some View {
        if AppSettings.shared.notchTimerStyle == .ruler {
            TimerRuler(timer: timer)
        } else {
            presetButtons
        }
    }

    private var presetButtons: some View {
        let columns = [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]
        return LazyVGrid(columns: columns, spacing: 7) {
            ForEach(TimerModel.presets, id: \.self) { minutes in
                Button {
                    timer.start(minutes: minutes)
                    NotchHaptics.tick()
                } label: {
                    VStack(spacing: 0) {
                        Text("\(minutes)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("min")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.11)))
                }
                .buttonStyle(NotchPress(scale: 0.93))
                .probe("timer.preset.\(minutes)")
            }
        }
        .padding(.top, 2)
        .transition(.blurReplace)
    }

    private var running: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.16), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(1 - timer.progress, 0.001))
                    .stroke(
                        timer.state == .finished ? Color.green : brandYellow,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                Text(timer.state == .finished ? "¡Listo!" : timer.text)
                    .font(.system(size: timer.state == .finished ? 13 : 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(width: 78, height: 78)

            VStack(spacing: 7) {
                Button {
                    timer.toggle()
                    NotchHaptics.tick()
                } label: {
                    Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 32)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(NotchPress(scale: 0.9))
                .probe("timer.toggle")

                Button {
                    timer.reset()
                    NotchHaptics.tick()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 44, height: 28)
                        .background(Capsule().fill(.white.opacity(0.08)))
                }
                .buttonStyle(NotchPress(scale: 0.9))
                .probe("timer.reset")
            }
        }
        .padding(.top, 2)
        .transition(.blurReplace)
    }
}

// MARK: - Battery and system

/// Battery, processor and memory.
private struct SystemWidget: View {

    @Bindable var system: SystemStatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            battery
            meter(label: "CPU", value: system.cpu, text: "\(Int((system.cpu * 100).rounded()))%", tint: brandYellow)
            meter(
                label: "RAM",
                value: system.memoryTotalGB > 0 ? system.memoryUsedGB / system.memoryTotalGB : 0,
                text: String(format: "%.1f / %.0f GB", system.memoryUsedGB, system.memoryTotalGB),
                tint: Color(red: 0.45, green: 0.78, blue: 1.0)
            )
        }
        .padding(.top, 4)
        // Read now, and every two seconds while the widget is on screen.
        .task {
            while !Task.isCancelled {
                system.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var battery: some View {
        if let percent = system.batteryPercent {
            HStack(spacing: 8) {
                Image(systemName: batterySymbol(percent))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(system.isCharging ? Color.green : (percent <= 20 ? Color.red : .white))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(percent)%")
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(batteryDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else {
            Label("Sin batería", systemImage: "powerplug.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        if system.isCharging { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var batteryDetail: String {
        guard let minutes = system.minutesRemaining else {
            return system.isCharging ? "Cargando" : (system.isOnAC ? "Conectado" : "Con batería")
        }
        let time = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        return system.isCharging ? "Cargando · \(time)" : "Quedan \(time)"
    }

    private func meter(label: String, value: Double, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(proxy.size.width * min(max(value, 0), 1), 4))
                        .animation(.smooth(duration: 0.5), value: value)
                }
            }
            .frame(height: 5)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .frame(minWidth: 40, alignment: .trailing)
        }
    }
}

// MARK: - Clipboard

/// The last things copied. A click puts one back on the clipboard.
private struct ClipboardWidget: View {

    @Bindable var clipboard: ClipboardModel

    var body: some View {
        Group {
            if clipboard.entries.isEmpty {
                EmptyNote(text: "Lo que copies aparecerá aquí")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(clipboard.entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                        Button {
                            clipboard.copy(entry)
                            NotchHaptics.tick()
                        } label: {
                            HStack(spacing: 7) {
                                if let thumbnail = entry.thumbnail {
                                    Image(nsImage: thumbnail)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 17, height: 17)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .frame(width: 17)
                                }
                                Text(entry.preview)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.7))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 23)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(index == 0 ? 0.09 : 0.04)))
                        }
                        .buttonStyle(NotchPress(scale: 0.97))
                        .onHover { clipboard.hover(entry, $0) }
                        .probe("clip.\(index)")
                    }
                }
                .animation(NotchMotion.swap, value: clipboard.entries)
                .padding(.top, 2)
                // A picture under the pointer is shown big over the list. It lets the pointer
                // through, so the row keeps its hover and a click still copies it.
                .overlay {
                    if let entry = clipboard.hoveredImage, let picture = entry.thumbnail {
                        ZStack(alignment: .bottomTrailing) {
                            Image(nsImage: picture)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(4)
                            Text(entry.preview)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .padding(5)
                        }
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.09)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 8)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .probe("clipboard.preview")
                    }
                }
                .animation(NotchMotion.swap, value: clipboard.hoveredID)
            }
        }
    }
}

// MARK: - Notifications

/// The last notifications that reached the notch. A click opens the app.
private struct NotificationsWidget: View {

    @Bindable var notifications: NotificationsModel

    var body: some View {
        Group {
            if !AppSettings.shared.notchNotifications {
                EmptyNote(text: "Activa las notificaciones en Ajustes › Notch › Avisos")
            } else if notifications.history.isEmpty {
                EmptyNote(text: "Las notificaciones que lleguen aparecerán aquí")
            } else {
                // Three rows is what fits under the header: more would push the whole
                // open notch out of place.
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(notifications.history.prefix(3).enumerated()), id: \.element.id) { index, item in
                        Button {
                            notifications.open(item)
                            NotchHaptics.tick()
                        } label: {
                            HStack(spacing: 7) {
                                NotificationIcon(notification: item, size: 15)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.shownHeadline)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.75))
                                    Text(item.appName)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(item.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .frame(height: 27)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(index == 0 ? 0.09 : 0.04)))
                        }
                        .buttonStyle(NotchPress(scale: 0.97))
                        .probe("notification.\(index)")
                    }
                }
                .animation(NotchMotion.swap, value: notifications.history.map(\.id))
                .padding(.top, 2)
            }
        }
    }
}
