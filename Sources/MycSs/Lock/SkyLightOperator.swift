import AppKit
import CoreGraphics
import Foundation

/// Places a window in the WindowServer Space that the lock screen lives in, so it
/// renders above the lock UI.
///
/// **Why private APIs**: macOS has no public API for third-party content on the
/// lock screen. The mechanism is to move the window into a *Space* that the lock
/// screen occupies, at a Space level above the one normal windows live in.
///
/// **Why these exact symbols**: `SkyLight.framework` is private, so nothing here
/// is contractual. Every symbol is resolved at runtime with `dlsym` and every
/// level constant is read from the loaded image rather than hard-coded, so a
/// macOS update that renames or relocates something degrades to a normal window
/// instead of crashing.
///
/// **How the lock screen's Space is found**: `loginwindow` owns the windows of
/// the lock screen, and `SLSCopySpacesForWindows` reports which Space each of
/// its windows is in. Asking "where is the lock screen?" is therefore answered
/// directly, by asking the window server.
///
/// The earlier approach — comparing Space *ids* to notice that a new one had
/// appeared — was fragile: Space ids are not ordered the way one would assume
/// across sessions, so a fresh lock could fail to be noticed and the overlay
/// would only show on the *second* lock.
final class SkyLight {

    // MARK: - Types

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32) -> Unmanaged<CFArray>?
    private typealias SpaceTypeFn = @convention(c) (Int32, UInt64) -> Int32
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SetAbsoluteLevelFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias SetWindowLevelFn = @convention(c) (Int32, UInt32, Int32) -> Int32
    private typealias SpaceDestroyFn = @convention(c) (Int32, UInt64) -> Void

    /// The Space type the lock screen uses. Verified on this machine: enumerating
    /// spaces while unlocked yields 15 spaces of type 3.
    private static let lockSpaceType: Int32 = 3

    /// The owner of the lock screen's windows.
    private static let lockScreenOwner = "loginwindow"

    /// The mask for `SLSCopySpacesForWindows`: every kind of Space.
    ///
    /// With the smaller mask that is usually used (the interactive and the
    /// full screen ones) the lock screen's Space is not returned at all, and
    /// the window cannot be checked to be there.
    private static let allSpacesMask: Int32 = 0x7F

    // MARK: - Symbol resolution

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
        RTLD_NOW
    )

    /// Resolves a private symbol to a callable function pointer.
    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type.self)
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

    static let shared = SkyLight()

    private init() {
        if Self.handle == nil {
            Log.error("skylight: framework unavailable, lock screen overlay disabled")
        }
    }

    // MARK: - Connection

    /// Resolves the symbols and opens the connection, before it is needed.
    ///
    /// The first lock is the one that has to work, and doing this work at the
    /// moment of the lock costs a tenth of a second — the overlay is on screen
    /// but not yet lifted above the lock screen.
    func prepare() {
        guard ensureConnection() != nil else { return }
        Log.line("skylight: ready")
    }

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

    // MARK: - Finding the lock screen's Space

    /// The Space that the lock screen's windows live in.
    ///
    /// This is the reliable answer to "where is the lock screen right now?": the
    /// window server is asked which Space the `loginwindow` windows are in.
    ///
    /// It only works **while the screen is actually locked**: with the Mac
    /// unlocked, `loginwindow` has a window that belongs to no Space at all, and
    /// this returns `nil`. So it is the second strategy, not the first.
    func lockScreenSpace() -> UInt64? {
        guard let conn = ensureConnection(),
              let copySpacesForWindows = Self.resolve(
                  "SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)
        else { return nil }

        // The windows of the lock screen.
        guard let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let numbers = windowList.compactMap { window -> Int? in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == Self.lockScreenOwner
            else { return nil }
            return window[kCGWindowNumber as String] as? Int
        }
        guard !numbers.isEmpty else { return nil }

        // All the spaces those windows are in, in one call.
        guard let spaces = copySpacesForWindows(conn, 7, numbers as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return nil }

        // `loginwindow` has more than one window, and some of them keep
        // belonging to the spaces of the *previous* locks. Only a space that
        // the lock has just created is of any use: the others are not being
        // displayed, and putting the overlay there means not seeing it.
        for space in spaces {
            let id = space.uint64Value
            guard spaceType(conn, id) == Self.lockSpaceType else { continue }
            guard !spacesBeforeLock.contains(id) else { continue }
            Log.line("skylight: lock screen is in space \(id)")
            return id
        }

        return nil
    }

    /// The spaces that existed before the screen was locked.
    ///
    /// The lock screen gets a Space of its own, and it is a *new* one: the
    /// spaces of the previous locks are gone by the time the screen is locked
    /// again. So the lock screen's Space is the one of type 3 that was not
    /// there before the lock — and that is the only way to tell it apart from
    /// the leftovers of the last lock, which are what makes the overlay
    /// invisible the first time the screen is locked after the app starts.
    private var spacesBeforeLock: Set<UInt64> = []

    /// Remembers the spaces of the current session.
    func rememberSpaces() {
        spacesBeforeLock = Set(allSpaces().map { $0.0 })
    }

    /// The lock screen's Space, if it is a new one.
    func newLockSpace() -> UInt64? {
        for (id, type) in allSpaces() where type == Self.lockSpaceType {
            guard !spacesBeforeLock.contains(id) else { continue }
            return id
        }
        return nil
    }

    /// Every space of the display, with its type.
    private func allSpaces() -> [(UInt64, Int32)] {
        guard let conn = ensureConnection(),
              let copySpaces = Self.resolve("SLSCopySpaces", as: CopySpacesFn.self),
              let all = copySpaces(conn, 0xFFFF)?.takeRetainedValue() as? [NSNumber]
        else { return [] }

        return all.map { ($0.uint64Value, spaceType(conn, $0.uint64Value)) }
    }

    /// The type of a space.
    private func spaceType(_ conn: Int32, _ id: UInt64) -> Int32 {
        guard let getType = Self.resolve("SLSSpaceGetType", as: SpaceTypeFn.self) else { return -1 }
        return getType(conn, id)
    }

    /// The spaces of the display, with their type, for the log.
    ///
    /// The ids on their own say nothing: they are not ordered by age, and the
    /// list changes while the screen is locking. The types are what tell the
    /// lock screen's space apart from the desktop's.
    func describeSpaces() -> String {
        guard let conn = ensureConnection(),
              let copySpaces = Self.resolve("SLSCopySpaces", as: CopySpacesFn.self),
              let all = copySpaces(conn, 0xFFFF)?.takeRetainedValue() as? [NSNumber]
        else { return "?" }

        return all.map { "\($0.uint64Value):\(spaceType(conn, $0.uint64Value))" }
            .joined(separator: " ")
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

        let windowNumber = window.windowNumber
        guard windowNumber != 0 else {
            Log.warn("skylight: window has no number yet, cannot elevate")
            return false
        }

        // The Space of the lock screen.
        //
        // Two ways to find it, and the order matters:
        //
        // 1. The Space the `loginwindow` windows are in. This is authoritative
        //    but only becomes available *after* the lock screen has been drawn —
        //    while the Mac is unlocked, `loginwindow` has a window that belongs
        //    to no Space at all.
        // 2. The first type-3 Space in the window server's list. This works from
        //    the moment of the lock, because the lock screen's Space is created
        //    along with it.
        //
        // Both are tried, and the second one is used as the fallback, so the
        // overlay appears on the first lock and not only from the second one on.
        if let space = lockScreenSpace() ?? newLockSpace() {
            addWindows(conn, space, [windowNumber] as CFArray, 7)
            setWindowLevel(window)

            // The window has to be presented again in the Space it has just
            // been moved to.
            //
            // A window that is *created* while the screen is locking is not
            // drawn in the Space it is moved to: it stays invisible until it is
            // presented there.
            present(window, in: space)

            // The move fails when the Space does not exist yet, which happens
            // on the first lock: the Space of the lock screen is created a
            // moment after the notification. The Space is only remembered when
            // the window really arrived, so that the next tick tries again.
            if isInSpace(space, window: window) {
                currentLockSpace = space
                Log.line("skylight: window \(windowNumber) joined lock space \(space)")
                isActive = true
                return true
            }

            Log.line("skylight: the move to space \(space) did not take, will try again")
            return false
        }

        // Last resort: create our own Space at the lock screen's absolute level.
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
        _ = setLevel(conn, UInt32(window.windowNumber), level)
    }

    /// The level the overlay is drawn at: above everything, including the
    /// lock screen.
    private var level: Int32 = Int32(CGShieldingWindowLevel()) + 1

    /// Moves the window again if the lock screen has created a new Space.
    ///
    /// The lock screen's Space does not exist at the moment the overlay is first
    /// shown: the window server creates it a fraction of a second later. So the
    /// window is placed in the best known lock Space and then **moved again** as
    /// soon as the real one appears — that is the Space the lock screen is
    /// actually being drawn in.
    ///
    /// Without this the overlay stays in the Space of the *previous* lock, which
    /// is not being displayed, and the user sees nothing.
    ///
    /// - Parameter window: the window that should follow the lock screen.
    /// - Returns: `true` when the window was moved to a different Space.
    @discardableResult
    func followLockScreenSpace(of window: NSWindow) -> Bool {
        guard let conn = ensureConnection(),
              let addWindows = Self.resolve(
                  "SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsFn.self)
        else { return false }

        let windowNumber = window.windowNumber
        guard windowNumber != 0 else { return false }

        // The Space the lock screen's own windows are in, when it is known.
        if let space = lockScreenSpace(), space != currentLockSpace {
            addWindows(conn, space, [windowNumber] as CFArray, 7)
            setWindowLevel(window)
            present(window, in: space)
            if isInSpace(space, window: window) {
                currentLockSpace = space
                Log.line("skylight: window followed the lock screen into space \(space)")
                return true
            }
        }

        // Otherwise, the Space that the lock just created.
        if let space = newLockSpace(), space != currentLockSpace {
            addWindows(conn, space, [windowNumber] as CFArray, 7)
            setWindowLevel(window)
            present(window, in: space)
            if isInSpace(space, window: window) {
                currentLockSpace = space
                Log.line("skylight: window moved to lock space \(space)")
                return true
            }
        }

        // The window is in the right Space but it is not being drawn. That is
        // what happens the first time the screen is locked after the app
        // starts: the window is created at the very moment of the lock, and
        // the window server does not draw it in the Space it is moved to.
        // Presenting it again is what makes it appear.
        if currentLockSpace != 0, !isOnScreen(window) {
            present(window, in: currentLockSpace)
            Log.line("skylight: the window was not being drawn, presented again")
            return true
        }

        return false
    }

    /// Whether the window server is drawing the window.
    ///
    /// A window that is created at the very moment of the lock is not drawn
    /// in the Space it is moved to: it stays invisible until it is presented
    /// again.
    func isOnScreen(_ window: NSWindow) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            .optionIncludingWindow,
            CGWindowID(window.windowNumber)
        ) as? [[String: Any]], let info = list.first else { return false }

        return (info["kCGWindowIsOnscreen"] as? NSNumber)?.boolValue ?? false
    }

    /// Whether the window really is in the given Space.
    ///
    /// Moving a window to a Space that does not exist yet fails silently, so
    /// the move has to be checked: if the window did not arrive, the Space is
    /// left as the current one, so that the next tick tries again.
    func isInSpace(_ space: UInt64, window: NSWindow) -> Bool {
        guard let conn = ensureConnection(),
              let copySpacesForWindows = Self.resolve(
                  "SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self),
              let spaces = copySpacesForWindows(
                  conn,
                  Self.allSpacesMask,
                  [window.windowNumber] as CFArray
              )?.takeRetainedValue() as? [NSNumber]
        else { return false }

        return spaces.contains { $0.uint64Value == space }
    }

    /// The state of the window, for the log.
    ///
    /// `kCGWindowIsOnscreen` is the important one: it says whether the window
    /// server considers the window on screen, which is not the same as the app
    /// thinking it is visible.
    func describe(_ window: NSWindow) -> String {
        var parts: [String] = []

        if let conn = ensureConnection(),
           let copySpacesForWindows = Self.resolve(
               "SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self),
           let spaces = copySpacesForWindows(conn, 7, [window.windowNumber] as CFArray)?
               .takeRetainedValue() as? [NSNumber] {
            parts.append("spaces \(spaces.map { $0.uint64Value })")
        }

        if let list = CGWindowListCopyWindowInfo(
            .optionIncludingWindow, CGWindowID(window.windowNumber)
        ) as? [[String: Any]], let info = list.first {
            let level = info["kCGWindowLevel"] as? Int ?? 0
            let alpha = info["kCGWindowAlpha"] as? Double ?? 0
            let onscreen = info["kCGWindowIsOnscreen"] as? Bool ?? false
            parts.append("level \(level) alpha \(alpha) onscreen \(onscreen)")
        }

        parts.append("visible \(window.isVisible)")
        return parts.joined(separator: " ")
    }

    /// Presents the window in the Space it has just been moved to.
    ///
    /// The move puts the window in the Space, but the window server only
    /// draws it there when it is presented again. The level is set once more
    /// because presenting a window puts it back at its normal level.
    private func present(_ window: NSWindow, in space: UInt64) {
        window.orderFrontRegardless()
        setWindowLevel(window)
    }

    /// The Space the overlay is currently in.
    private var currentLockSpace: UInt64 = 0


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
