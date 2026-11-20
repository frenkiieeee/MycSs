import Foundation
import ObjectiveC

/// The backlight of the built-in keyboard, through `KeyboardBrightnessClient` of the
/// private `CoreBrightness` framework (the class macOS itself uses), loaded at run
/// time. If the framework, the class or a method is not there, or the Mac has no
/// keyboard light, every call fails and the key is left to the system.
enum KeyboardBacklight {

    private typealias GetFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFunction = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias FlagFunction = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    /// The client and the class it comes from, or nil when this macOS has no such thing.
    private static let client: (object: NSObject, type: AnyClass)? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        // A missing method would send the call to the forwarding stub and crash.
        for selector in [getSelector, setSelector, idsSelector] where !type.instancesRespond(to: selector) {
            Log.warn("keyboard light: \(NSStringFromSelector(selector)) is not there")
            return nil
        }
        return (type.init(), type)
    }()

    /// The id of the keyboard to move: the built-in one, or the first with a light.
    /// Looked up once; a Mac keeps its built-in keyboard.
    private static var cachedID: UInt64??

    private static func keyboardID() -> UInt64? {
        if let cachedID { return cachedID }
        guard let (object, type) = client,
              let result = object.perform(idsSelector)?.takeUnretainedValue() as? [NSNumber]
        else { return nil }
        var chosen = result.first?.uint64Value
        if type.instancesRespond(to: builtInSelector) {
            let isBuiltIn = unsafeBitCast(class_getMethodImplementation(type, builtInSelector), to: FlagFunction.self)
            if let builtIn = result.first(where: { isBuiltIn(object, builtInSelector, $0.uint64Value) }) {
                chosen = builtIn.uint64Value
            }
        }
        cachedID = .some(chosen)
        return chosen
    }

    /// Whether this Mac has a keyboard light MycSs can move.
    static var isAvailable: Bool { keyboardID() != nil }

    /// From 0 to 1, or nil when there is no light.
    static func level() -> Float? {
        guard let (object, type) = client, let id = keyboardID() else { return nil }
        let function = unsafeBitCast(class_getMethodImplementation(type, getSelector), to: GetFunction.self)
        let value = function(object, getSelector, id)
        return value.isFinite ? min(max(value, 0), 1) : nil
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let (object, type) = client, let id = keyboardID() else { return false }
        let function = unsafeBitCast(class_getMethodImplementation(type, setSelector), to: SetFunction.self)
        return function(object, setSelector, min(max(value, 0), 1), id)
    }

    /// Moves the light one step and says where it went, or nil when there is no light
    /// (the key then goes to the system).
    static func step(up: Bool, by step: Float = 1.0 / 16.0) -> Float? {
        guard let current = level() else { return nil }
        let target = min(max(up ? current + step : current - step, 0), 1)
        return set(target) ? target : nil
    }
}
