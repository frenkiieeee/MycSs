import Observation
import SwiftUI

/// The entrance animation for the overlay.
///
/// The lock screen appears immediately, and an overlay that pops in on top of it
/// looks like a glitch. These entrances make it arrive deliberately.
///
/// **Why it is driven by the visible flag and not by `onAppear`**: `onAppear` only
/// fires the first time a view enters the hierarchy. The overlay's view is created
/// once and then shown and hidden repeatedly, so an entrance built on `onAppear`
/// animates the first time and stays invisible every time after that. Driving it
/// from the `visible` flag means every appearance gets the animation.
///
/// The animation state lives in an `@Observable` object rather than in `@State`,
/// because the Command Line Tools do not ship the SwiftUI macros plugin that
/// `@State` needs.
struct EntranceModifier: ViewModifier {

    var entrance: AppSettings.Entrance
    /// How far the entrance has come, from 0 to 1.
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(scale)
            .offset(y: offset)
    }

    private var scale: CGFloat {
        switch entrance {
        case .fade: return 0.98 + 0.02 * progress
        case .fall, .rise: return 0.96 + 0.04 * progress
        }
    }

    private var offset: CGFloat {
        switch entrance {
        case .fade: return 0
        case .fall: return -60 * (1 - progress)
        case .rise: return 60 * (1 - progress)
        }
    }
}

