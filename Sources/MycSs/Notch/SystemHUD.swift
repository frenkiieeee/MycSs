import ApplicationServices
import AppKit
import CoreAudio
import Foundation
import CoreGraphics

/// What the notch shows when the volume, the brightness or the keyboard light changes.
struct NotchHUD: Equatable {
    enum Kind: Equatable {
        case volume
        case brightness
        /// The light of the keyboard.
        case keyboard
    }
    var kind: Kind
    /// From 0 to 1.
    var value: Float
    var muted: Bool = false

    /// Where the indicator points, from 0 to 1: nothing when muted.
    var shownValue: CGFloat { muted ? 0 : CGFloat(min(max(value, 0), 1)) }
}

// MARK: - Volume

/// The volume of the default output device.
///
/// It uses the *virtual main volume*, the same control the keyboard keys move, so
/// it works on every device that has a volume (not on HDMI or some DACs, which
/// have none; then the key is left to the system).
enum SystemAudio {

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// `'vmvc'`: the virtual main volume.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    static func defaultOutput() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func volume() -> Float? {
        guard let device = defaultOutput() else { return nil }
        var property = address(virtualMainVolume)
        guard AudioObjectHasProperty(device, &property) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    @discardableResult
    static func setVolume(_ value: Float) -> Bool {
        guard let device = defaultOutput() else { return false }
        var property = address(virtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &property),
              AudioObjectIsPropertySettable(device, &property, &settable) == noErr,
              settable.boolValue
        else { return false }
        var clamped = Float32(min(max(value, 0), 1))
        let status = AudioObjectSetPropertyData(
            device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &clamped
        )
        return status == noErr
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutput() else { return false }
        var property = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutput() else { return false }
        var property = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &property),
              AudioObjectIsPropertySettable(device, &property, &settable) == noErr,
              settable.boolValue
        else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(
            device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        ) == noErr
    }
}

// MARK: - Watching the volume

/// Tells when the volume or the mute of the output changes, whoever changed it:
/// the keys, Control Centre, the headphones. It needs no permission, so the notch
/// can show the volume even when it is not allowed to take the keys.
final class VolumeWatcher {

    /// Called on the main thread with the new volume.
    var onChange: ((NotchHUD) -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var registered: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var last: NotchHUD?

    func start() {
        guard registered.isEmpty else { return }
        // A different output device (headphones plugged in) has its own volume.
        var defaultDevice = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachToDevice()
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, block
        ) == noErr {
            registered.append((AudioObjectID(kAudioObjectSystemObject), defaultDevice, block))
        }
        attachToDevice()
    }

    func stop() {
        for (object, address, block) in registered {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        registered.removeAll()
        device = AudioDeviceID(kAudioObjectUnknown)
        last = nil
    }

    private func attachToDevice() {
        guard let current = SystemAudio.defaultOutput(), current != device else { return }

        // Drop the listeners of the old device, keep the one on the system.
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (object, address, block) in registered where object != system {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        registered.removeAll { $0.0 != system }
        device = current
        last = snapshot()

        // The virtual main volume is what the keys move; the per-channel volume
        // is listened to as well, because some devices only announce that one.
        let selectors: [(AudioObjectPropertySelector, UInt32)] = [
            (0x766D_7663, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element
            )
            guard AudioObjectHasProperty(current, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.report()
            }
            if AudioObjectAddPropertyListenerBlock(current, &address, .main, block) == noErr {
                registered.append((current, address, block))
            }
        }
    }

    private func snapshot() -> NotchHUD? {
        guard let volume = SystemAudio.volume() else { return nil }
        return NotchHUD(kind: .volume, value: volume, muted: SystemAudio.isMuted())
    }

    private func report() {
        // Several listeners fire for one change; only a real change is told.
        guard let now = snapshot(), now != last else { return }
        last = now
        onChange?(now)
    }
}

// MARK: - Brightness

/// The brightness of the built-in display, through the private
/// `DisplayServices` framework, loaded at run time. If it is not there, or the
/// display has no brightness, every call fails and the key is left to the system.
enum DisplayBrightness {

    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    static func get(_ display: CGDirectDisplayID) -> Float? {
        guard let function = symbol("DisplayServicesGetBrightness", as: GetFunction.self) else { return nil }
        var value: Float = 0
        return function(display, &value) == 0 ? value : nil
    }

    @discardableResult
    static func set(_ value: Float, on display: CGDirectDisplayID) -> Bool {
        guard let function = symbol("DisplayServicesSetBrightness", as: SetFunction.self) else { return false }
        return function(display, min(max(value, 0), 1)) == 0
    }
}

// MARK: - The keys

/// Takes the volume and brightness keys, changes the value itself and tells the
/// notch to draw it, so the system's own indicator does not appear.
///
/// **It needs the Accessibility permission.** A tap that can *swallow* a key (and
/// so keep the system from drawing its indicator) is only allowed for trusted
/// apps. Without the permission, `install` fails and the keys keep working as
/// they always did. macOS ties the permission to the app's signature; an ad-hoc
/// signature changes with every build, so the permission has to be given again
/// after each one (see `scripts/make-dev-cert.sh`).
///
/// A key is only swallowed when its change really happened. If the output device
/// has no volume, or the display no brightness, the key goes through to the
/// system untouched.
final class MediaKeyTap {

    static let shared = MediaKeyTap()

    /// Called, on the main thread, with what to draw.
    var onChange: ((NotchHUD) -> Void)?
    /// Whether the keys should be taken right now. When the notch is not on
    /// screen (locked, or the lyrics are up) they go to the system.
    var isActive: () -> Bool = { true }
    /// The display whose brightness the brightness keys move.
    var brightnessDisplay: CGDirectDisplayID = CGMainDisplayID()
    /// While a shortcut is being recorded, every key that could be one comes here
    /// (with its modifiers and what it types) instead of acting.
    var recorder: ((_ code: Int, _ modifiers: Int, _ character: String) -> Void)?

    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { port != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's own prompt that leads to the Accessibility settings.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func install() -> Bool {
        guard port == nil else { return true }
        guard Self.isTrusted else { return false }

        // `NX_SYSDEFINED` (14): where the volume and brightness keys arrive. The
        // ordinary key events are for the keyboard light shortcut, in the keyboard
        // mode where F1 and F2 are plain keys, and for the shortcuts the user records.
        let mask: CGEventMask = (1 << 14)
            | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.warn("hud: the event tap could not be created")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        Log.line("hud: volume and brightness keys are now taken")
        return true
    }

    func uninstall() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.port = nil
        self.source = nil
        Log.line("hud: volume and brightness keys are back to the system")
    }

    // MARK: - Events

    // Key codes of `NX_KEYTYPE_*`.
    private enum Key: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // The system switches a slow tap off; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        }
        if type == .keyDown || type == .keyUp { return handleKey(type: type, event: event) }

        guard type.rawValue == 14,
              let ns = NSEvent(cgEvent: event),
              ns.type == .systemDefined,
              ns.subtype.rawValue == 8
        else { return pass }

        let data = ns.data1
        let code = (data & 0xFFFF_0000) >> 16
        let flags = data & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0xA
        let modifiers = KeyChord.modifiers(event.flags)

        // A media key is the F key it stands for, so a shortcut made of it (the
        // default ⌥F2) is looked at before the volume and brightness keys are.
        if let function = KeyChord.functionKey(forMediaKey: code) {
            switch shortcut(code: function, modifiers: modifiers, isDown: isDown, character: "") {
            case .swallow: return nil
            case .ignore: break
            }
        }

        guard AppSettings.shared.notchHUD, isActive(), let key = Key(rawValue: code) else { return pass }

        // Option and Shift together move by a quarter step, like in macOS.
        let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        guard isDown else {
            // The release of a key whose press was taken is taken too.
            if taken.remove(key.rawValue) != nil { return nil }
            return pass
        }

        guard let hud = apply(key, step: step) else {
            taken.remove(key.rawValue)
            return pass
        }
        taken.insert(key.rawValue)
        DispatchQueue.main.async { [weak self] in self?.onChange?(hud) }
        return nil
    }

    // MARK: - The keyboard light shortcut

    private enum Outcome { case swallow, ignore }

    /// Ordinary keys: the shortcut of the keyboard light with F1 and F2 as plain keys,
    /// or any combination the user recorded.
    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = KeyChord.modifiers(event.flags)
        let isDown = type == .keyDown

        // Typing never gets here: only an F key or a key with a modifier is looked at.
        // A release is always looked at: the modifier may be let go before the key.
        guard !isDown || KeyChord.isValid(code: code, modifiers: modifiers) else { return pass }
        let character = isDown ? (NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? "") : ""
        switch shortcut(code: code, modifiers: modifiers, isDown: isDown, character: character) {
        case .swallow: return nil
        case .ignore: return pass
        }
    }

    /// A shortcut being recorded, or one of the keyboard light. It says whether the
    /// key was used (and so must not reach the system).
    private func shortcut(code: Int, modifiers: Int, isDown: Bool, character: String) -> Outcome {
        if let recorder {
            // The release of a key that was recorded is taken too.
            if !isDown { return takenLight.remove(code) != nil ? .swallow : .ignore }
            guard KeyChord.isValid(code: code, modifiers: modifiers) else { return .ignore }
            takenLight.insert(code)
            DispatchQueue.main.async { recorder(code, modifiers, character) }
            return .swallow
        }

        let settings = AppSettings.shared
        guard settings.keyboardLightEnabled else { return .ignore }
        guard isDown else { return takenLight.remove(code) != nil ? .swallow : .ignore }
        guard let direction = KeyboardLightDirection.direction(
            code: code, modifiers: modifiers, up: settings.keyboardLightUp, down: settings.keyboardLightDown
        ) else { return .ignore }

        // No light on this Mac: the key is left to the system.
        guard let level = KeyboardBacklight.step(up: direction == .up) else { return .ignore }
        takenLight.insert(code)
        let hud = NotchHUD(kind: .keyboard, value: level)
        DispatchQueue.main.async { [weak self] in self?.onChange?(hud) }
        return .swallow
    }

    /// The keys whose press was used as a shortcut, so their release is taken too.
    private var takenLight: Set<Int> = []

    /// The keys whose last press this tap took, so their release is taken too.
    private var taken: Set<Int> = []

    private func apply(_ key: Key, step: Float) -> NotchHUD? {
        switch key {
        case .soundUp, .soundDown:
            guard let current = SystemAudio.volume() else { return nil }
            var muted = SystemAudio.isMuted()
            let target = key == .soundUp ? current + step : current - step
            if key == .soundUp, muted {
                SystemAudio.setMuted(false)
                muted = false
            }
            guard SystemAudio.setVolume(target) else { return nil }
            let value = min(max(target, 0), 1)
            return NotchHUD(kind: .volume, value: value, muted: muted)

        case .mute:
            guard SystemAudio.setMuted(!SystemAudio.isMuted()) else { return nil }
            let muted = SystemAudio.isMuted()
            return NotchHUD(kind: .volume, value: SystemAudio.volume() ?? 0, muted: muted)

        case .brightnessUp, .brightnessDown:
            guard let current = DisplayBrightness.get(brightnessDisplay) else { return nil }
            let target = key == .brightnessUp ? current + step : current - step
            guard DisplayBrightness.set(target, on: brightnessDisplay) else { return nil }
            return NotchHUD(kind: .brightness, value: min(max(target, 0), 1))
        }
    }
}
