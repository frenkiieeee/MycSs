import AppKit
import CoreGraphics

/// The cover of a browser tab: the page's icon in the middle of a square of its own
/// colour (spec 014). An icon is small (16 to 180 px), so it is drawn at a size it
/// can bear and the square around it carries the colour the theme takes.
enum BrowserCover {

    static let side = 512

    /// PNG data of the cover; with no icon, a globe.
    static func make(icon data: Data?) -> Data? {
        let image = data.flatMap(NSImage.init(data:)) ?? globe()
        // A vector icon (many favicons are SVG) is drawn at the size of the cover, not
        // at its own tiny one.
        if let image, !image.representations.contains(where: { $0 is NSBitmapImageRep }) {
            image.size = NSSize(width: 256, height: 256)
        }
        guard let image, let icon = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let side = CGFloat(Self.side)
        guard let context = CGContext(
            data: nil, width: Self.side, height: Self.side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // The background: the icon's average colour, from a little darker at the
        // bottom to a little lighter at the top.
        let base = averageColour(icon) ?? (0.25, 0.25, 0.28)
        let top = CGColor(srgbRed: lift(base.0, 0.18), green: lift(base.1, 0.18), blue: lift(base.2, 0.18), alpha: 1)
        let bottom = CGColor(srgbRed: base.0 * 0.45, green: base.1 * 0.45, blue: base.2 * 0.45, alpha: 1)
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [bottom, top] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])
        }

        // The icon, at most four times its own size so a tiny one does not turn to mush.
        let natural = CGFloat(max(icon.width, icon.height))
        let size = min(side * 0.46, max(natural * 4, side * 0.3))
        let rect = CGRect(x: (side - size) / 2, y: (side - size) / 2, width: size, height: size)
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: CGColor(gray: 0, alpha: 0.45))
        context.interpolationQuality = natural < 64 ? .medium : .high
        context.draw(icon, in: rect)

        guard let result = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
    }

    private static func lift(_ value: CGFloat, _ amount: CGFloat) -> CGFloat {
        min(value + (1 - value) * amount, 1)
    }

    private static func globe() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 120, weight: .regular)
            .applying(.init(paletteColors: [.white]))
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    /// The average colour of the opaque pixels, nudged towards a colour with some
    /// life (a white icon on a white page would give a grey background).
    static func averageColour(_ image: CGImage) -> (CGFloat, CGFloat, CGFloat)? {
        let width = 24, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, weight: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = CGFloat(pixels[index]) / 255 / alpha
            let g = CGFloat(pixels[index + 1]) / 255 / alpha
            let b = CGFloat(pixels[index + 2]) / 255 / alpha
            // Saturated pixels count more: they are the brand's colour.
            let saturation = max(r, g, b) - min(r, g, b)
            let w = 0.2 + saturation * 2
            red += r * w; green += g * w; blue += b * w; weight += w
        }
        guard weight > 0 else { return nil }
        return (min(red / weight, 1), min(green / weight, 1), min(blue / weight, 1))
    }
}
