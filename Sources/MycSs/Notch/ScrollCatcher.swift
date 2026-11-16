import AppKit
import SwiftUI

/// Catches the horizontal scroll of a trackpad (two fingers to the sides) over the
/// view it is put on, which SwiftUI cannot do outside a scroll view.
///
/// It lets everything else through: clicks, hover and vertical scrolls go to what
/// is underneath. Only a scroll event is handed to it.
struct ScrollCatcher: NSViewRepresentable {

    /// Set by the self test while it sends a scroll straight to the window, which
    /// the application does not list as its current event.
    nonisolated(unsafe) static var isTesting = false

    /// Called with how much to move, in points, and whether this is the start of
    /// a new gesture.
    var onScroll: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {

        var onScroll: ((CGFloat, Bool) -> Void)?

        // Only scroll events find this view; every other event goes through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            (ScrollCatcher.isTesting || NSApp.currentEvent?.type == .scrollWheel) ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            let horizontal = abs(event.scrollingDeltaX)
            let vertical = abs(event.scrollingDeltaY)
            // A mostly vertical scroll is not ours.
            guard horizontal > vertical else {
                super.scrollWheel(with: event)
                return
            }
            // A wheel (not a trackpad) moves in whole lines: one line, one step.
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 26
            onScroll?(delta, event.phase.contains(.began) || event.phase == .mayBegin)
        }
    }
}
