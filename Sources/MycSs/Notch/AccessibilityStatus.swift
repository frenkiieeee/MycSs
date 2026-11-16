import ApplicationServices
import AppKit
import Observation
import Security

/// Whether MycSs has the Accessibility permission, kept up to date.
///
/// The settings window used to read the permission once, when it was drawn, so it
/// went on saying "missing" after the user had granted it. This object looks
/// again every second and tells everyone who is watching.
@MainActor
@Observable
final class AccessibilityStatus {

    static let shared = AccessibilityStatus()

    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private var timer: Timer?

    /// Starts looking. Safe to call more than once.
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        let now = AXIsProcessTrusted()
        guard now != isTrusted else { return }
        isTrusted = now
        Log.line("hud: the Accessibility permission is now \(now ? "granted" : "missing")")
    }

    // MARK: - Asking

    /// Shows the system's prompt, which also puts MycSs in the Accessibility list,
    /// and opens that list. An app without a Dock icon has to come forward first or
    /// the prompt can fail to appear.
    func request() {
        NSApp.activate(ignoringOtherApps: true)
        MediaKeyTap.requestTrust()
        openSettings()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows MycSs.app in the Finder, to drag it into the Accessibility list by hand.
    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Forgets MycSs's Accessibility entry, then asks again.
    ///
    /// When the app is signed with a different identity than the one that was
    /// granted (a new build signed another way), macOS keeps the old entry in the
    /// list, shows it as on, and does not honour it, and the prompt does not appear
    /// because an entry exists. Removing it, with `tccutil`, lets the prompt work.
    /// It only touches MycSs's own entry.
    func resetAndRequest() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.mycss.lyrics"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            Log.line("hud: the Accessibility entry was reset (\(process.terminationStatus))")
        } catch {
            Log.warn("hud: tccutil could not run: \(error.localizedDescription)")
        }
        AppSettings.shared.accessibilityPromptedFor = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.request()
        }
    }
}

/// Who the running app is, as macOS sees it. It is what a permission is tied to.
enum AppIdentity {

    /// The designated requirement of this build: `cdhash …` for an ad-hoc build
    /// (so it changes with every build) or `identifier … and certificate leaf = …`
    /// for one signed with a certificate (which does not).
    static var requirement: String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text
        else { return "unknown" }
        return text as String
    }
}
