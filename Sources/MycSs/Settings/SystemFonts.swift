import AppKit
import CoreText
import Foundation

/// The fonts installed on the system, for the font picker.
///
/// The list is built with CoreText, which sees every font the system has,
/// including the ones AppKit's font manager hides. On this machine there are
/// around 2,700.
///
/// **The system font is a special case**: Apple's own typeface (SF Pro) cannot
/// be requested by name — CoreText refuses to hand out the system fonts, and
/// falls back to Times — so it is represented by a sentinel and resolved
/// through `NSFont.systemFont`, which is the only correct way to get it.
enum SystemFonts {

    /// One selectable font.
    struct Entry: Identifiable, Hashable {
        /// The PostScript name, used to create the font.
        var postScriptName: String
        /// The family name, shown in the picker.
        var familyName: String
        /// The style name (Regular, Bold, Italic...).
        var styleName: String

        var id: String { postScriptName }

        var displayName: String {
            styleName.isEmpty || styleName == "Regular"
                ? familyName
                : "\(familyName) — \(styleName)"
        }
    }

    /// The name that stands for Apple's system font.
    static let systemFontSentinel = "__system__"

    private static var cached: [Entry]?

    /// All installed fonts, sorted by family name.
    ///
    /// The system font comes first, because it is the app's default.
    static func all() -> [Entry] {
        if let cached { return cached }
        var entries: [Entry] = [
            Entry(
                postScriptName: systemFontSentinel,
                familyName: "SF Pro (sistema)",
                styleName: ""
            )
        ]
        entries.append(contentsOf: build())
        cached = entries
        return entries
    }

    private static func build() -> [Entry] {
        var entries: [Entry] = []

        // The fonts in the standard locations.
        var searchPaths = [
            "/System/Library/Fonts",
            "/Library/Fonts",
            NSHomeDirectory() + "/Library/Fonts",
        ]
        // Fonts installed by applications live in their own bundles.
        if let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            searchPaths.append(applicationSupport.path(percentEncoded: false) + "/Fonts")
        }

        for path in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
            for file in contents where file.hasSuffix(".ttf") || file.hasSuffix(".otf") || file.hasSuffix(".ttc") {
                let url = URL(fileURLWithPath: path).appendingPathComponent(file)
                entries.append(contentsOf: descriptors(at: url))
            }
        }

        // Deduplicate by PostScript name and sort for the picker.
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.postScriptName).inserted }
        return unique.sorted {
            $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedSame
        }
    }

    /// Reads the font descriptors of a single file.
    private static func descriptors(at url: URL) -> [Entry] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        return descriptors.compactMap { descriptor in
            guard let postScriptName = CTFontDescriptorCopyAttribute(
                descriptor, kCTFontNameAttribute) as? String
            else { return nil }

            let family = (CTFontDescriptorCopyAttribute(
                descriptor, kCTFontFamilyNameAttribute) as? String) ?? postScriptName
            let style = (CTFontDescriptorCopyAttribute(
                descriptor, kCTFontStyleNameAttribute) as? String) ?? ""

            return Entry(
                postScriptName: postScriptName,
                familyName: family,
                styleName: style
            )
        }
    }

    /// Creates a font.
    ///
    /// The system font is resolved through `NSFont.systemFont`, because it cannot
    /// be created by name. Any other font falls back to the system font when the
    /// name is unknown.
    static func font(postScriptName: String, size: CGFloat) -> NSFont {
        if postScriptName == systemFontSentinel {
            return NSFont.systemFont(ofSize: size, weight: .bold)
        }
        return NSFont(name: postScriptName, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
    }
}
