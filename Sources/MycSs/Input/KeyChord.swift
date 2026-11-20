import AppKit
import Carbon.HIToolbox

/// A key and the modifiers held with it: what a recorded shortcut is.
///
/// The key is a virtual key code (`kVK_*`). The media keys of the function row
/// (brightness, volume) arrive as another kind of event, but they are the same keys
/// as F1 to F12 of an Apple keyboard, so they are stored as the F key they are: the
/// same shortcut works whichever mode the keyboard is in.
struct KeyChord: Equatable {
    /// A `kVK_*` code.
    var code: Int
    /// Carbon modifier bits (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: Int
    /// What the key is called when it is not an F key, to write it in the label.
    var character: String = ""

    // MARK: - The F keys

    /// Virtual key codes of F1 to F20, and their names.
    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static func isFunctionKey(_ code: Int) -> Bool { functionKeys[code] != nil }

    /// The F key a media key stands for on an Apple keyboard (`NX_KEYTYPE_*`):
    /// brightness F1 and F2, previous, play and next F7 to F9, mute, volume down
    /// and volume up F10 to F12.
    static func functionKey(forMediaKey media: Int) -> Int? {
        switch media {
        case 3: return 122
        case 2: return 120
        case 18: return 98
        case 16: return 100
        case 17: return 101
        case 7: return 109
        case 1: return 103
        case 0: return 111
        default: return nil
        }
    }

    // MARK: - Modifiers

    /// Carbon bits of a set of Core Graphics flags, keeping only the four that count.
    static func modifiers(_ flags: CGEventFlags) -> Int {
        var result = 0
        if flags.contains(.maskCommand) { result |= cmdKey }
        if flags.contains(.maskShift) { result |= shiftKey }
        if flags.contains(.maskAlternate) { result |= optionKey }
        if flags.contains(.maskControl) { result |= controlKey }
        return result
    }

    /// Whether a combination can be a shortcut: an ordinary key needs Control,
    /// Option or Command (or it would steal what is typed); an F key does not.
    static func isValid(code: Int, modifiers: Int) -> Bool {
        isFunctionKey(code) || modifiers & (controlKey | optionKey | cmdKey) != 0
    }

    // MARK: - Text

    /// What the shortcut shows: ⌥F2.
    var label: String {
        HotKeyManager.symbols(modifiers) + (Self.functionKeys[code] ?? character.uppercased())
    }

    /// How it is stored in the settings.
    var stored: String { "\(code)|\(modifiers)|\(character)" }

    init(code: Int, modifiers: Int, character: String = "") {
        self.code = code
        self.modifiers = modifiers
        self.character = character
    }

    init?(stored: String) {
        let parts = stored.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, let code = Int(parts[0]), let modifiers = Int(parts[1]) else { return nil }
        self.init(code: code, modifiers: modifiers, character: parts.count > 2 ? String(parts[2]) : "")
    }

    // MARK: - Matching

    /// Whether a pressed key is this shortcut. The modifiers have to be exactly
    /// these: ⌥⇧F1 is not ⌥F1 (it is still the fine step of the screen brightness).
    func matches(code: Int, modifiers: Int) -> Bool {
        self.code == code && self.modifiers == modifiers
    }
}

/// The two shortcuts that move the keyboard light.
enum KeyboardLightDirection {
    case up, down

    /// The default shortcuts: ⌥F2 up, ⌥F1 down.
    static let defaultUp = KeyChord(code: 120, modifiers: optionKey)
    static let defaultDown = KeyChord(code: 122, modifiers: optionKey)

    /// Which way a pressed key moves the light, if it is one of the shortcuts.
    static func direction(code: Int, modifiers: Int, up: KeyChord?, down: KeyChord?) -> KeyboardLightDirection? {
        if up?.matches(code: code, modifiers: modifiers) == true { return .up }
        if down?.matches(code: code, modifiers: modifiers) == true { return .down }
        return nil
    }
}
