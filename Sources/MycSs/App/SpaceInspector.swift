import AppKit
import CoreGraphics
import Foundation

/// A diagnostic that reports what the window server is doing, so the lock screen
/// behaviour can be inspected instead of guessed at.
///
/// It is a separate tool because it needs to answer questions about the *other*
/// processes' windows, which the app itself cannot see from inside.
///
/// Run it as: `./inspect-spaces`
enum SpaceInspector {

    static func run() {
        let connection = SkyLightProbe.connection()
        print("== Space inspector ==")
        print("connection: \(connection)\n")

        print("-- display's current Space --")
        if let spaces = SkyLightProbe.managedDisplaySpaces(connection) {
            for (index, space) in spaces.enumerated() {
                print("  display \(index): current space \(space.id) (type \(space.type))")
            }
        }

        print("\n-- the Spaces, in the order the window server returns them --")
        for (index, space) in SkyLightProbe.allSpaces(connection).enumerated() {
            let marker = space.type == 3 ? "  <- lock screen" : ""
            print(String(format: "  [%2ld] %5lld (type %ld)%@",
                         index, space.id, space.type, marker))
            if index > 5 { break }
        }

        print("\n-- loginwindow --")
        for entry in SkyLightProbe.windows(ownedBy: "loginwindow") {
            let spaces = SkyLightProbe.spaces(ofWindow: entry.number, connection: connection)
            let description = spaces.isEmpty
                ? "in no space"
                : spaces.map { "\($0.id)(type \($0.type))" }.joined(separator: ", ")
            print("  window \(entry.number): \(description)  (on screen: \(entry.onScreen))")
        }

        print("\n-- MycSs --")
        let mine = SkyLightProbe.windows(ownedBy: "MycSs")
        if mine.isEmpty {
            print("  (no window)")
        }
        for entry in mine {
            let spaces = SkyLightProbe.spaces(ofWindow: entry.number, connection: connection)
            let description = spaces.isEmpty
                ? "in no space"
                : spaces.map { "\($0.id)(type \($0.type))" }.joined(separator: ", ")
            print("  window \(entry.number): layer \(entry.layer), \(description), on screen: \(entry.onScreen)")
        }
    }
}

/// Thin wrapper over the private SkyLight calls, used by the inspector.
enum SkyLightProbe {

    struct Space {
        var id: UInt64
        var type: Int32
    }

    struct WindowInfo {
        var number: Int
        var layer: Int
        var onScreen: Bool
    }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceTypeFn = @convention(c) (Int32, UInt64) -> Int32
    private typealias ManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
        RTLD_NOW
    )

    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type.self)
    }

    static func connection() -> Int32 {
        resolve("SLSMainConnectionID", as: ConnFn.self)?() ?? 0
    }

    /// Every Space the window server knows about.
    static func allSpaces(_ connection: Int32) -> [Space] {
        guard let copy = resolve("SLSCopySpaces", as: CopySpacesFn.self),
              let all = copy(connection, 0xFFFF)?.takeRetainedValue() as? [NSNumber]
        else { return [] }

        let getType = resolve("SLSSpaceGetType", as: SpaceTypeFn.self)
        return all.compactMap { entry in
            let id = entry.uint64Value
            let type = getType?(connection, id) ?? -1
            return Space(id: id, type: type)
        }
    }

    /// The Spaces of type 3, which are the lock screens.
    static func lockSpaces(_ connection: Int32) -> [Space] {
        allSpaces(connection).filter { $0.type == 3 }.sorted { $0.id < $1.id }
    }

    /// The current Space of each display.
    static func managedDisplaySpaces(_ connection: Int32) -> [(id: UInt64, type: Int32)]? {
        guard let copy = resolve("SLSCopyManagedDisplaySpaces", as: ManagedDisplaySpacesFn.self),
              let all = copy(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }

        return all.compactMap { entry in
            guard let current = entry["Current Space"] as? [String: Any],
                  let id = current["id64"] as? NSNumber
            else { return nil }
            let type = current["type"] as? NSNumber
            return (id.uint64Value, type?.int32Value ?? -1)
        }
    }

    /// The Spaces a window belongs to.
    static func spaces(ofWindow number: Int, connection: Int32) -> [Space] {
        guard let copy = resolve("SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)
        else { return [] }

        let numbers = [number] as CFArray
        guard let all = copy(connection, 7, numbers)?.takeRetainedValue() as? [NSNumber]
        else { return [] }

        let getType = resolve("SLSSpaceGetType", as: SpaceTypeFn.self)
        return all.map { id in
            Space(id: id.uint64Value, type: getType?(connection, id.uint64Value) ?? -1)
        }
    }

    /// The windows owned by a given application.
    static func windows(ownedBy owner: String) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        return list.compactMap { window in
            guard let name = window[kCGWindowOwnerName as String] as? String, name == owner,
                  let number = window[kCGWindowNumber as String] as? Int
            else { return nil }
            let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
            let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
            return WindowInfo(number: number, layer: layer, onScreen: onScreen)
        }
    }
}
