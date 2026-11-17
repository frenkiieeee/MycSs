import SwiftUI
import UniformTypeIdentifiers

// MARK: - Debug probes

/// Set while a capture is being drawn. The renderer that makes the captures
/// paints a warning square over any drop target and skips scroll views, so both
/// are left out of captures. It is never set in the running app.
enum NotchSnapshot {
    nonisolated(unsafe) static var isActive = false
}

/// Where the controls are, recorded only for the self test, which clicks on them.
enum NotchProbe {
    nonisolated(unsafe) static var isOn = false
    nonisolated(unsafe) static var frames: [String: CGRect] = [:]
}

extension View {
    /// Records the frame of a control for the self test. Does nothing otherwise.
    @ViewBuilder
    func probe(_ id: String) -> some View {
        if NotchProbe.isOn {
            background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { NotchProbe.frames[id] = frame }
                        .onChange(of: frame) { _, new in NotchProbe.frames[id] = new }
                }
            }
        } else {
            self
        }
    }
}
