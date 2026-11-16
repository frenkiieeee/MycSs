import AppKit
import Carbon.HIToolbox

/// The global shortcut that shows the lyrics.
///
/// It uses Carbon's `RegisterEventHotKey`, which is old but is still the way to
/// get a system-wide shortcut **without asking for any permission**: the system
/// itself delivers the key press, so the app never has to read the keyboard.
/// (An event tap would need Accessibility or Input Monitoring.)
final class HotKeyManager {

    static let shared = HotKeyManager()

    /// Called when the shortcut is pressed, on the main thread.
    var onPress: (() -> Void)?

    /// Posted after the shortcut changes, so the menu can show the new one.
    static let didChange = Notification.Name("MycSsHotKeyDidChange")

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers the shortcut that is in the settings, replacing the old one.
    func reload() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        defer { NotificationCenter.default.post(name: Self.didChange, object: nil) }

        let settings = AppSettings.shared
        guard settings.hotKeyEnabled else { return }
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x4D594353), id: 1)  // "MYCS"
        let status = RegisterEventHotKey(
            UInt32(settings.hotKeyCode),
            UInt32(settings.hotKeyModifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Log.warn("hotkey: could not register \(settings.hotKeyLabel) (status \(status))")
        } else {
            Log.line("hotkey: registered \(settings.hotKeyLabel)")
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    // MARK: - Conversions

    /// Carbon modifier bits from AppKit's flags.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        return result
    }

    /// AppKit's flags from Carbon modifier bits.
    static func appKitModifiers(_ carbon: Int) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbon & cmdKey != 0 { result.insert(.command) }
        if carbon & shiftKey != 0 { result.insert(.shift) }
        if carbon & optionKey != 0 { result.insert(.option) }
        if carbon & controlKey != 0 { result.insert(.control) }
        return result
    }

    /// The symbols for a set of modifiers, in the order macOS writes them.
    static func symbols(_ carbon: Int) -> String {
        (carbon & controlKey != 0 ? "⌃" : "")
            + (carbon & optionKey != 0 ? "⌥" : "")
            + (carbon & shiftKey != 0 ? "⇧" : "")
            + (carbon & cmdKey != 0 ? "⌘" : "")
    }
}
