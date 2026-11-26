import AppKit
import ApplicationServices

/// Closes the system's banner of a notification that the notch already shows
/// (spec 012, ADR 003). Experimental.
///
/// macOS draws the banner in its `NotificationCenter` process and no app can stop
/// it from appearing; but with **Accessibility** another app can press the banner's
/// own «Close» action once it is there, which is what this does. The banner is
/// found by its subrole (`AXNotificationCenter…`) or by having a close action, and
/// is only closed when its text matches the notification, so another one that
/// happens to be on screen is left alone. It is looked for during a few seconds,
/// because the banner is drawn a moment after the notification is written.
///
/// Closing it also takes it out of Notification Centre; the notch keeps it in its
/// history. The tree of the banner changes between versions of macOS: every attempt
/// leaves a line in the log, and `--banner-probe` prints the tree to adjust it.
@MainActor
final class SystemBannerCloser {

    /// Words the close action is called by, in the languages a Mac is likely to use.
    nonisolated static let closeWords = ["close", "cerrar", "fermer", "schließen", "chiudi", "fechar", "sluiten", "閉じる", "关闭", "닫기", "закрыть"]

    private var pending: [NotchNotification] = []
    private var task: Task<Void, Never>?

    /// Starts looking for the banner of a notification.
    func close(matching notification: NotchNotification) {
        guard AXIsProcessTrusted() else {
            Log.line("banner: cannot close the system's banner without Accessibility")
            return
        }
        pending.append(notification)
        guard task == nil else { return }
        task = Task { [weak self] in
            // Every 80 ms for up to 3 s after the last notification asked for it.
            var lastFound = Date()
            while !Task.isCancelled, let self, !self.pending.isEmpty {
                if self.sweep() { lastFound = Date() }
                if Date().timeIntervalSince(lastFound) > 3 {
                    for missed in self.pending {
                        Log.line("banner: no banner found for \(missed.appName) (run --banner-probe to see the tree)")
                    }
                    self.pending.removeAll()
                    break
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            self?.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        pending.removeAll()
    }

    // MARK: - Looking

    /// One look at the banners on screen; true when one was closed.
    private func sweep() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first
        else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        let windows = Self.children(root, kAXWindowsAttribute)
        var closedAny = false
        for window in windows {
            for banner in Self.banners(in: window, depth: 0) {
                let text = Self.text(of: banner).lowercased()
                guard let index = pending.firstIndex(where: { Self.matches($0, text: text) }) else { continue }
                if Self.pressClose(banner) {
                    Log.line("banner: closed the system's banner of \(pending[index].appName)")
                    pending.remove(at: index)
                    closedAny = true
                }
            }
        }
        return closedAny
    }

    /// Whether a banner's text is this notification's: its title, or the start of its
    /// body, appears in it.
    nonisolated static func matches(_ notification: NotchNotification, text: String) -> Bool {
        let candidates = [notification.title, notification.body, notification.subtitle]
            .map { String($0.prefix(40)).lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        guard !candidates.isEmpty else { return false }
        return candidates.contains { text.contains($0) }
    }

    /// Whether an action name or its description says "close".
    nonisolated static func isClose(_ name: String, description: String) -> Bool {
        let haystack = (name + " " + description).lowercased()
        return closeWords.contains { haystack.contains($0) }
    }

    /// The elements that look like a banner: the `AXNotificationCenter…` subroles,
    /// or anything with a close action that is not a widget.
    private static func banners(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 9 else { return [] }
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        if identifier.hasPrefix("widget-") { return [] }
        if subrole.hasPrefix("AXNotificationCenter"), subrole != "AXNotificationCenterAlertStack" {
            return [element]
        }
        if closeAction(element) != nil, depth > 0 { return [element] }
        return children(element, kAXChildrenAttribute).flatMap { banners(in: $0, depth: depth + 1) }
    }

    private static func closeAction(_ element: AXUIElement) -> String? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let list = names as? [String] else { return nil }
        for name in list {
            var description: CFString?
            AXUIElementCopyActionDescription(element, name as CFString, &description)
            if isClose(name, description: (description as String?) ?? "") { return name }
        }
        return nil
    }

    /// Presses the close action, or a close button inside the banner.
    private static func pressClose(_ banner: AXUIElement) -> Bool {
        if let action = closeAction(banner) {
            return AXUIElementPerformAction(banner, action as CFString) == .success
        }
        for child in children(banner, kAXChildrenAttribute) {
            let role = string(child, kAXRoleAttribute) ?? ""
            let label = [string(child, kAXDescriptionAttribute), string(child, kAXTitleAttribute)]
                .compactMap { $0 }.joined(separator: " ")
            if role == kAXButtonRole as String, isClose("", description: label) {
                return AXUIElementPerformAction(child, kAXPressAction as CFString) == .success
            }
            if pressClose(child) { return true }
        }
        return false
    }

    /// All the text of an element and what is inside it.
    private static func text(of element: AXUIElement, depth: Int = 0) -> String {
        guard depth < 6 else { return "" }
        var parts: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let value = string(element, attribute), !value.isEmpty { parts.append(value) }
        }
        for child in children(element, kAXChildrenAttribute) {
            parts.append(text(of: child, depth: depth + 1))
        }
        return parts.joined(separator: " ")
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
