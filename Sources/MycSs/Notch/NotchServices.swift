import Foundation

/// Everything the notch's views read, in one place, so a view takes one thing and
/// not eight. The settings preview builds one with demo data.
@MainActor
final class NotchServices {

    let agenda: AgendaModel
    let shelf: ShelfModel
    let reminders: RemindersModel
    let timer: TimerModel
    let system: SystemStatsModel
    let clipboard: ClipboardModel
    let notifications: NotificationsModel

    init(demo: Bool = DemoFlags.isDemo) {
        agenda = AgendaModel(demo: demo)
        shelf = ShelfModel()
        reminders = RemindersModel(demo: demo)
        timer = TimerModel()
        system = SystemStatsModel()
        clipboard = ClipboardModel(demo: demo)
        notifications = NotificationsModel(demo: demo)
    }
}
