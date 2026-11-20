import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records a `KeyChord`: click it, press the combination, done.
///
/// It records the media keys too (the brightness keys are F1 and F2), which only the
/// event tap sees, so while it records the tap sends it the keys instead of acting
/// on them. Without the tap (no Accessibility permission) it still records ordinary
/// keys, through a local monitor. Esc cancels, Delete clears the shortcut.
struct ChordRecorder: NSViewRepresentable {
    var chord: KeyChord?
    var onChange: (KeyChord?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.chord = chord
        button.onChange = onChange
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = onChange
        guard !button.isRecording else { return }
        button.chord = chord
    }

    final class RecorderButton: NSButton {

        var chord: KeyChord? { didSet { if !isRecording { refreshTitle() } } }
        var onChange: ((KeyChord?) -> Void)?
        private(set) var isRecording = false
        private var monitor: Any?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            target = self
            action = #selector(beginRecording)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        deinit { endRecording() }

        override var acceptsFirstResponder: Bool { true }

        func refreshTitle() {
            title = chord?.label ?? "Sin atajo"
        }

        @objc private func beginRecording() {
            guard !isRecording else { return }
            isRecording = true
            title = "Pulsa el atajo…"
            window?.makeFirstResponder(self)

            // The tap hears the media keys; the monitor, the rest when there is no tap.
            MediaKeyTap.shared.recorder = { [weak self] code, modifiers, character in
                self?.finish(code: code, modifiers: modifiers, character: character)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                return self.handle(event) ? nil : event
            }
        }

        private func endRecording() {
            isRecording = false
            MediaKeyTap.shared.recorder = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func resignFirstResponder() -> Bool {
            endRecording()
            refreshTitle()
            return super.resignFirstResponder()
        }

        /// Esc, Delete and the combinations that reach the window; true when used.
        private func handle(_ event: NSEvent) -> Bool {
            let code = Int(event.keyCode)
            if code == kVK_Escape {
                window?.makeFirstResponder(nil)
                return true
            }
            if code == kVK_Delete || code == kVK_ForwardDelete {
                commit(nil)
                return true
            }
            let modifiers = HotKeyManager.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            finish(code: code, modifiers: modifiers, character: event.charactersIgnoringModifiers ?? "")
            return true
        }

        private func finish(code: Int, modifiers: Int, character: String) {
            guard isRecording else { return }
            guard KeyChord.isValid(code: code, modifiers: modifiers) else {
                NSSound.beep()
                return
            }
            // A key that has no name of its own needs its character for the label.
            guard KeyChord.isFunctionKey(code) || !character.isEmpty else { return }
            commit(KeyChord(code: code, modifiers: modifiers, character: character))
        }

        private func commit(_ new: KeyChord?) {
            chord = new
            onChange?(new)
            window?.makeFirstResponder(nil)
        }
    }
}
