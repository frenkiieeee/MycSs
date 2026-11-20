import AppKit
import SwiftUI

// MARK: - Pictures of the previews

/// `MycSs --demo --settings-snapshot <prefix>`: draws the settings previews to PNG
/// files (the real settings window cannot be captured while the screen is
/// locked). Every style is tried and then undone, so the user's settings are left
/// as they were.
@MainActor
enum SettingsPreviewSnapshot {

    /// While the pictures are drawn, the previews are not stopped when the renderer
    /// drops them.
    nonisolated(unsafe) static var isRunning = false

    static func run(prefix: String, completion: @escaping () -> Void) {
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            let undo = PresetUndo.shared
            let defaults = UserDefaults.standard
            let before = defaults.dictionaryRepresentation()
            OverlayPreview.model.startPreview()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-default.png", width: 440)

            for preset in StylePreset.allCases {
                undo.run { preset.apply(to: AppSettings.shared) }
                try? await Task.sleep(nanoseconds: 900_000_000)
                write(OverlayPreviewCard(), "\(prefix)-overlay-\(preset.rawValue).png", width: 440)
            }
            undo.undo()
            // Without the clock, and with it back again.
            undo.run { AppSettings.shared.showClock = false }
            try? await Task.sleep(nanoseconds: 900_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-noclock.png", width: 440)
            undo.undo()
            try? await Task.sleep(nanoseconds: 900_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-clockback.png", width: 440)

            // The user's own styles: make, use, change, update and delete one.
            let library = StyleLibrary.shared
            let settings = AppSettings.shared
            settings.clockSize = 150
            library.draftName = "Prueba"
            library.createFromCurrent(.lyrics)
            let made = library.items(.lyrics).first { !$0.isBuiltIn }
            let madeID = made?.id ?? ""
            var ok = made?.title == "Prueba" && library.state(of: madeID, .lyrics) == .active
            settings.clockSize = 70
            ok = ok && library.state(of: madeID, .lyrics) == .modified
            library.apply(madeID, .lyrics)
            ok = ok && settings.clockSize == 150 && library.state(of: madeID, .lyrics) == .active
            library.apply("builtin.minimal", .lyrics)
            ok = ok && library.state(of: madeID, .lyrics) == .inactive && settings.showClock == false
            library.apply(madeID, .lyrics)
            ok = ok && settings.showClock == true
            library.beginEditing(madeID)
            library.editName = "Renombrada"
            library.commitRename()
            ok = ok && library.items(.lyrics).contains { $0.title == "Renombrada" }
            library.delete(madeID, .lyrics)
            ok = ok && !library.items(.lyrics).contains { !$0.isBuiltIn }
            print("settings snapshot: custom styles \(ok ? "OK" : "!! FAILED")")
            // Back to how it was.
            undo.undo()
            for key in ["clockSize", "showClock", "activeStyle.lyrics", "activeStyleValues.lyrics", "customStyles"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            OverlayPreview.model.stopPreview()

            let state = NotchPreviewState.shared
            NotchSnapshot.isActive = true
            state.start()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for scene in NotchPreviewScene.allCases {
                state.show(scene)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                write(NotchPreviewCard(), "\(prefix)-notch-\(scene.rawValue).png", width: 700)
            }
            for look in NotchLook.allCases {
                undo.run { look.apply(to: AppSettings.shared) }
                state.show(.open)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                write(NotchPreviewCard(), "\(prefix)-notch-look-\(look.rawValue).png", width: 700)
            }
            undo.undo()

            // Every indicator, at the same value, to judge each look.
            let appSettings = AppSettings.shared
            state.show(.volume)
            for hud in AppSettings.NotchHUDStyle.allCases {
                appSettings.notchHUDStyle = hud
                state.step(0, kind: .volume)
                try? await Task.sleep(nanoseconds: 700_000_000)
                write(NotchPreviewCard(), "\(prefix)-hud-\(hud.rawValue).png", width: 700)
            }
            appSettings.notchHUDStyle = .bar
            appSettings.notchHUDNumber = .hidden
            state.step(0, kind: .volume)
            try? await Task.sleep(nanoseconds: 700_000_000)
            write(NotchPreviewCard(), "\(prefix)-hud-nonumber.png", width: 700)
            for key in ["notchHUDStyle", "notchHUDNumber"] { UserDefaults.standard.removeObject(forKey: key) }

            // A style seen without applying it: the picture changes, the settings do not.
            let viewedBefore = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("notch") || $0.key.hasPrefix("clock") }
            let previewer = StylePreviewer.shared
            if let item = StyleLibrary.shared.items(.notch).first(where: { $0.id == "builtin.showy" }) {
                state.show(.open)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                previewer.toggle(item, .notch)
                write(NotchPreviewCard(), "\(prefix)-viewing-notch.png", width: 700)
                previewer.stop()
            }
            if let item = StyleLibrary.shared.items(.lyrics).first(where: { $0.id == "builtin.frenkiieeee" }) {
                OverlayPreview.model.startPreview()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                previewer.toggle(item, .lyrics)
                write(OverlayPreviewCard(), "\(prefix)-viewing-lyrics.png", width: 440)
                previewer.stop()
                OverlayPreview.model.stopPreview()
            }
            // The change of song, with animation on (the pictures above are taken without it):
            // with lyrics to with lyrics, to none, and back.
            isRunning = false
            do {
                let m = OverlayPreview.model
                m.startPreview()
                m.previewWithoutLyrics = false
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let first = m.lyrics?.lines.first?.text
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 120_000_000)
                let leaving = m.lyricsLeaving && m.lyrics?.lines.first?.text == first && m.lyricsReveal < 1
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let arrived = m.lyrics?.lines.first?.text != first && m.lyrics != nil && m.lyricsReveal == 1 && !m.lyricsLeaving
                m.previewWithoutLyrics = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let gone = m.lyrics == nil && m.lyricsNotFound
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 800_000_000)
                let stillNone = m.lyrics == nil && m.lyricsReveal == 0
                m.previewWithoutLyrics = false
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let back = m.lyrics != nil && m.lyricsReveal == 1 && !m.lyricsLeaving
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                print("settings snapshot: song change: old lyrics leave first \(leaving ? "OK" : "!! FAILED"), new ones arrive \(arrived ? "OK" : "!! FAILED"), none \(gone ? "OK" : "!! FAILED"), none to none \(stillNone ? "OK" : "!! FAILED"), none to lyrics \(back ? "OK" : "!! FAILED")")
                m.stopPreview()
            }
            isRunning = true

            // The lists of what a style stores: no key twice, none shared by both kinds, and a
            // reset puts every one of them back to its default (and can be undone).
            do {
                let lyricsKeys = StyleDomain.lyrics.keys, notchKeys = StyleDomain.notch.keys
                var coherent = Set(lyricsKeys).count == lyricsKeys.count
                    && Set(notchKeys).count == notchKeys.count
                    && Set(lyricsKeys).isDisjoint(with: Set(notchKeys))
                let appSettings = AppSettings.shared
                // What was stored before (nothing, or the user's own value), to leave it as it was.
                let stored = ["clockSize", "notchScale"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
                appSettings.clockSize = 123
                appSettings.notchScale = 1.2
                SettingsReset.reset([.lyrics, .notch])
                let cleared = (lyricsKeys + notchKeys).allSatisfy { UserDefaults.standard.object(forKey: $0) == nil }
                coherent = coherent && cleared && appSettings.clockSize != 123 && appSettings.notchScale != 1.2
                PresetUndo.shared.undo()
                coherent = coherent && appSettings.clockSize == 123 && appSettings.notchScale == 1.2
                for (key, value) in stored {
                    if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
                }
                print("settings snapshot: style key lists and reset: \(coherent ? "OK" : "!! FAILED")")
            }

            // The volume indicator on the lock screen and the lyrics (the notch is hidden there).
            do {
                let m = OverlayPreview.model
                let source = NotchModel()
                m.hudSource = source
                m.startPreview()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                source.showHUD(NotchHUD(kind: .volume, value: 0.62), for: 30)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                write(OverlayPreviewCard(), "\(prefix)-overlay-hud.png", width: 440)
                print("settings snapshot: overlay indicator: \(source.hud != nil ? "OK" : "!! FAILED")")
                m.hudSource = nil
                m.stopPreview()
            }

            let viewedAfter = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("notch") || $0.key.hasPrefix("clock") }
            print("settings snapshot: viewing a style does not apply it: \(NSDictionary(dictionary: viewedBefore).isEqual(to: viewedAfter) ? "OK" : "!! FAILED")")

            state.stop()
            NotchSnapshot.isActive = false
            let after = defaults.dictionaryRepresentation()
            let changed = Set(before.keys).union(after.keys).filter { !$0.hasPrefix("METAL_") && !$0.hasPrefix("NS") && (before[$0] as? NSObject) != (after[$0] as? NSObject) }
            print(changed.isEmpty
                  ? "settings snapshot: the user's settings are as they were"
                  : "settings snapshot: !! left changed: \(changed.sorted())")
            completion()
        }
    }

    private static func write<V: View>(_ view: V, _ path: String, width: CGFloat) {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .padding(12)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
