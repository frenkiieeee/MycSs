import AppKit
import CoreGraphics
import Foundation

/// Places a window in the WindowServer Space that the lock screen lives in, so it
/// renders above the lock UI.
///
/// **Why private APIs**: macOS has no public API for third-party content on the
/// lock screen. The mechanism is to move the window into a *Space* that the lock
/// screen owns, at a Space level above the one normal windows live in.
///
/// **Why these exact symbols**: `SkyLight.framework` is private, so nothing here
/// is contractual. Every symbol is resolved at runtime with `dlsym` and every
/// level constant is read from the loaded image rather than hard-coded, so a
/// macOS update that renames or relocates something degrades to a normal window
/// instead of crashing.
///
/// **Why the existing-Space strategy**: creating a brand new Space at a high
/// absolute level (300/400) is the more obvious approach, but it is also the
/// more dangerous one — during development, creating an elevated Space from a
/// bare console process destabilised the shell session. Joining the Space the
/// lock screen already uses is gentler: the Space is already at the right level,
/// the app only has to move its window into it.
final class SkyLight {

    // MARK: - Types

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32) -> Unmanaged<CFArray>?
    private typealias SpaceTypeFn = @convention(c) (Int32, UInt64) -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SetAbsoluteLevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias SetWindowLevelFn = @convention(c) (Int32, UInt32, Int32) -> Int32
    private typealias SpaceDestroyFn = @convention(c) (Int32, UInt64) -> Void

    /// The Space type the lock screen uses. Verified on this machine: enumerating
    /// spaces while unlocked yields 15 spaces of type 3, and the newest one is the
    /// one created for the most recent lock.
    private static let lockSpaceType: Int32 = 3

    // MARK: - Symbol resolution

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
        RTLD_NOW
    )

    /// Resolves a private symbol to a callable function pointer.
    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    /// Reads an exported `Int32` constant by name.
    ///
    /// The level constants are read from the loaded image instead of being
    /// written as literals: only `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`
    /// is guaranteed to be exported, and its value may change between releases.
    private static func constant(_ name: String) -> Int32? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return symbol.assumingMemoryBound(to: Int32.self).pointee
    }

    // MARK: - State

    private var connection: Int32 = 0
    private var fallbackSpace: UInt64 = 0
    private var resolvedConnection = false

    /// True when the private API was usable and a window was successfully lifted.
    private(set) var isActive = false

    /// The newest lock-screen Space id observed. Compared against to detect that a
    /// *new* lock has happened (a fresh Space is created per lock).
    private(set) var newestLockSpaceID: UInt64 = 0

    static let shared = SkyLight()

    private init() {
        if Self.handle == nil {
            Log.error("skylight: framework unavailable, lock screen overlay disabled")
        }
    }

    // MARK: - Connection

    private func ensureConnection() -> Int32? {
        if resolvedConnection { return connection == 0 ? nil : connection }
        resolvedConnection = true
        guard let mainConn = Self.resolve("SLSMainConnectionID", as: MainConnectionIDFn.self) else {
            Log.error("skylight: SLSMainConnectionID missing")
            return nil
        }
        connection = mainConn()
        Log.line("skylight: connection id = \(connection)")
        return connection
    }

    // MARK: - Space discovery

    /// Returns the id of the newest Space of type 3 (the lock screen's Space).
    ///
    /// A fresh Space is created on each lock, so the newest one is the live lock
    /// screen. Spaces of other types are ignored.
    func newestLockSpace() -> UInt64? {
        guard let conn = ensureConnection(),
              let copySpaces = Self.resolve("SLSCopySpaces", as: CopySpacesFn.self),
              let getType = Self.resolve("SLSSpaceGetType", as: SpaceTypeFn.self),
              let all = copySpaces(conn, 0xFFFF)?.takeRetainedValue() as? [NSNumber]
        else { return nil }

        var newest: UInt64 = 0
        for entry in all {
            let id = entry.uint64Value
            guard getType(conn, id) == Self.lockSpaceType else { continue }
            if id > newest { newest = id }
        }
        guard newest != 0 else { return nil }
        newestLockSpaceID = newest
        return newest
    }

    // MARK: - Elevation

    /// Moves `window` into the lock screen's Space so it renders above the lock UI.
    ///
    /// - Parameter window: the window to lift. It must already be ordered front so
    ///   that the WindowServer has assigned it a window number.
    /// - Returns: `true` when the window was placed at lock-screen level.
    @discardableResult
    func elevate(_ window: NSWindow) -> Bool {
        guard let conn = ensureConnection(),
              let addWindows = Self.resolve(
                  "SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsFn.self)
        else {
            Log.error("skylight: required symbols missing, falling back to a normal window")
            return false
        }

        let windowNumber = UInt32(window.windowNumber)
        guard windowNumber != 0 else {
            Log.warn("skylight: window has no number yet, cannot elevate")
            return false
        }

        // Preferred path: join the Space the lock screen already created.
        if let space = newestLockSpace() {
            addWindows(conn, space, [windowNumber] as CFArray, 7)
            setWindowLevel(window)
            Log.line("skylight: window \(windowNumber) joined lock space \(space)")
            isActive = true
            return true
        }

        // Fallback: create our own Space at the lock screen's absolute level.
        // Only reached if the lock Space cannot be found (e.g. the app started
        // while already locked and no new Space was created).
        guard let create = Self.resolve("SLSSpaceCreate", as: SpaceCreateFn.self),
              let setLevel = Self.resolve("SLSSpaceSetAbsoluteLevel", as: SetAbsoluteLevelFn.self),
              let showSpaces = Self.resolve("SLSShowSpaces", as: ShowSpacesFn.self)
        else {
            Log.error("skylight: cannot create fallback space")
            return false
        }

        if fallbackSpace == 0 {
            let level = Self.constant("kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock") ?? 400
            fallbackSpace = create(conn, 1, nil)
            guard fallbackSpace != 0 else {
                Log.error("skylight: space creation failed")
                return false
            }
            _ = setLevel(conn, fallbackSpace, level)
            _ = showSpaces(conn, [fallbackSpace] as CFArray)
            Log.line("skylight: created fallback space \(fallbackSpace) at level \(level)")
        }

        addWindows(conn, fallbackSpace, [windowNumber] as CFArray, 7)
        setWindowLevel(window)
        Log.line("skylight: window \(windowNumber) joined fallback space \(fallbackSpace)")
        isActive = true
        return true
    }

    /// Raises the window's level so it sits above the shield/lock UI.
    private func setWindowLevel(_ window: NSWindow) {
        guard let conn = ensureConnection(),
              let setLevel = Self.resolve("SLSSetWindowLevel", as: SetWindowLevelFn.self)
        else { return }
        let target = Int32(CGShieldingWindowLevel()) + 1
        let result = setLevel(conn, UInt32(window.windowNumber), target)
        Log.line("skylight: window level set to \(target) (result \(result))")
    }

    /// Releases the fallback space, if one was created.
    func teardown() {
        guard fallbackSpace != 0, let conn = ensureConnection(),
              let destroy = Self.resolve("SLSSpaceDestroy", as: SpaceDestroyFn.self)
        else { return }
        destroy(conn, fallbackSpace)
        fallbackSpace = 0
        isActive = false
        Log.line("skylight: fallback space destroyed")
    }
}
