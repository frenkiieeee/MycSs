import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that records a keyboard shortcut.
///
/// Click it, press the combination, done. Escape cancels. The combination needs
/// at least one of Control, Option or Command, so it cannot swallow a plain key
/// that the user types everywhere.
struct HotKeyRecorder: NSViewRepresentable {

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.refreshTitle()
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.isRecording { button.refreshTitle() }
    }

    final class RecorderButton: NSButton {

        private(set) var isRecording = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            target = self
            action = #selector(beginRecording)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var acceptsFirstResponder: Bool { true }

        func refreshTitle() {
            let settings = AppSettings.shared
            title = settings.hotKeyEnabled ? settings.hotKeyLabel : "Sin atajo"
        }

        @objc private func beginRecording() {
            isRecording = true
            title = "Pulsa el atajo…"
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            refreshTitle()
            return super.resignFirstResponder()
        }

        // Command combinations arrive here first, before the menu sees them.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return super.performKeyEquivalent(with: event) }
            record(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            record(event)
        }

        private func record(_ event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                window?.makeFirstResponder(nil)
                return
            }
            // Delete clears the shortcut.
            if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                AppSettings.shared.hotKeyEnabled = false
                HotKeyManager.shared.reload()
                window?.makeFirstResponder(nil)
                return
            }
            let carbon = HotKeyManager.carbonModifiers(
                event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
            let needed = controlKey | optionKey | cmdKey
            guard carbon & needed != 0 else {
                NSSound.beep()
                return
            }
            let character = (event.charactersIgnoringModifiers ?? "").uppercased()
            guard !character.isEmpty else { return }

            let settings = AppSettings.shared
            settings.hotKeyCode = Int(event.keyCode)
            settings.hotKeyModifiers = carbon
            settings.hotKeyCharacter = character.lowercased()
            settings.hotKeyLabel = HotKeyManager.symbols(carbon) + character
            settings.hotKeyEnabled = true
            HotKeyManager.shared.reload()
            window?.makeFirstResponder(nil)
        }
    }
}
