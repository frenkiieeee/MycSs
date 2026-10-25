import Foundation
import IOKit.pwr_mgt

/// Controls whether the display stays on while the overlay is showing.
///
/// The overlay is only useful if the screen is actually on. macOS would
/// otherwise dim and sleep the display according to the Energy Saver settings,
/// and the lyrics would disappear.
///
/// Two modes are supported, and neither needs privileges:
///
/// - **keep**: a `PreventUserIdleDisplaySleep` assertion with no timeout, held
///   while the overlay is up and released when it goes away.
/// - **sleep after N minutes**: the same assertion but with a timeout, so it
///   expires on its own and the system takes the display down according to its
///   own policy.
///
/// The display cannot be switched off programmatically on this machine:
/// `IODisplayWrangler` has no `IOCommandQueue` child (so the classic
/// `SetPowerState` trick is unavailable) and `pmset displaysleepnow` needs
/// `sudo`. Letting the system sleep naturally is the honest behaviour.
enum DisplayPower {

    /// How the display should behave while the overlay is showing.
    enum Mode: Equatable {
        /// Never let the display sleep.
        case keepAwake
        /// Let the display sleep after the given number of minutes.
        case sleepAfter(minutes: Int)
    }

    private static var assertionID: IOPMAssertionID = 0
    private static var currentMode: Mode?

    /// Starts holding the display awake, or lets it sleep after a timeout.
    ///
    /// - Parameter mode: the desired behaviour.
    static func apply(_ mode: Mode) {
        guard mode != currentMode else { return }
        release()

        var properties: [String: Any] = [
            kIOPMAssertionTypeKey as String: kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            kIOPMAssertionNameKey as String: "MycSs showing lyrics on the lock screen",
            // The level is an integer, not a string.
            kIOPMAssertionLevelKey as String: kIOPMAssertionLevelOn,
        ]

        if case .sleepAfter(let minutes) = mode {
            properties[kIOPMAssertionTimeoutKey as String] = minutes * 60
            properties[kIOPMAssertionTimeoutActionKey as String] = kIOPMAssertionTimeoutActionTurnOff as String
        }

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(
            properties as CFDictionary,
            &id
        )

        if result == kIOReturnSuccess {
            assertionID = id
            currentMode = mode
            switch mode {
            case .keepAwake:
                Log.line("power: display held awake")
            case .sleepAfter(let minutes):
                Log.line("power: display will sleep after \(minutes) min")
            }
        } else {
            Log.error("power: could not create assertion (result \(result))")
        }
    }

    /// Releases the assertion, letting the system sleep the display normally.
    static func release() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        currentMode = nil
        Log.line("power: assertion released")
    }
}
