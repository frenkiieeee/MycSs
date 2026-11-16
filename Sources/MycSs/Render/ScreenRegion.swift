import SwiftUI

extension View {

    /// Tells the model where this view is on screen, so a click on it can be
    /// noticed even though the overlay is click-through on the lock screen.
    ///
    /// - Parameters:
    ///   - id: what the region is (`previous`, `playPause`, `next`, `seek`,
    ///     `cover`, `lyrics`, `eye`).
    ///   - active: when false the region is emptied, for a view that is still in
    ///     the hierarchy but should not count (the hidden lyrics column).
    func screenRegion(
        _ id: String,
        model: LyricsViewModel,
        display: CGDirectDisplayID,
        active: Bool = true
    ) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        model.setRegion(id, display: display, frame: active ? frame : .zero)
                    }
                    .onChange(of: frame) { _, new in
                        model.setRegion(id, display: display, frame: active ? new : .zero)
                    }
                    .onChange(of: active) { _, isActive in
                        model.setRegion(id, display: display, frame: isActive ? frame : .zero)
                    }
            }
        }
    }
}
