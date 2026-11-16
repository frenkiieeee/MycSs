import SwiftUI

/// The date and the time at the top of the screen.
///
/// Weight, design, colour, size and alignment come from the settings, so it can
/// go from the thin, light clock of the lock screen to a heavy yellow one.
struct ClockView: View {

    @Bindable var model: LyricsViewModel

    var body: some View {
        let settings = AppSettings.shared
        let leading = settings.clockAlignment == .leading
        let size = settings.clockSize

        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            VStack(alignment: leading ? .leading : .center, spacing: 4) {
                if settings.clockShowDate {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: max(size * 0.21, 16), weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.system(
                        size: size,
                        weight: settings.clockWeight.weight,
                        design: settings.clockDesign.design
                    ))
                    .foregroundStyle(color(settings.clockColor))
                    .shadow(color: model.theme.accent.color.opacity(0.35), radius: 34)
            }
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        }
    }

    private func color(_ choice: AppSettings.ClockColor) -> Color {
        switch choice {
        case .white: return .white
        case .glass: return .white.opacity(0.82)
        case .accent: return model.theme.accent.color
        case .yellow: return Color(red: 1.0, green: 0.831, blue: 0.0)
        }
    }
}
