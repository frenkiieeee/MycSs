import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// A colour with a role in the theme.
struct ThemeColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let white = ThemeColor(red: 1, green: 1, blue: 1)

    /// The colour as a SwiftUI colour.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// The colour as an AppKit colour.
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// A hexadecimal representation, for the log.
    var hex: String {
        String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    /// The relative luminance, used for contrast checks.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Scales the colour towards white, keeping it legible on a dark backdrop.
    func brightened(to minimum: Double) -> ThemeColor {
        let brightest = max(red, green, blue)
        guard brightest > 0.001, brightest < minimum else { return self }
        let factor = minimum / brightest
        return ThemeColor(
            red: min(red * factor, 1),
            green: min(green * factor, 1),
            blue: min(blue * factor, 1)
        )
    }

    /// Scales the colour towards black, for use as a background.
    func darkened(to factor: Double) -> ThemeColor {
        ThemeColor(red: red * factor, green: green * factor, blue: blue * factor)
    }

    /// The contrast ratio against another colour, per WCAG.
    func contrastRatio(against other: ThemeColor) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Linear interpolation towards another colour.
    func blended(towards other: ThemeColor, amount: Double) -> ThemeColor {
        let t = min(max(amount, 0), 1)
        return ThemeColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }
}

/// The colour theme derived from a track's artwork.
struct Theme: Equatable {
    /// The colour of the word being sung.
    var accent: ThemeColor
    /// The brighter supporting colour.
    var secondary: ThemeColor
    /// The darker end of the background gradient.
    var backgroundDeep: ThemeColor
    /// The lighter end of the background gradient.
    var backgroundMid: ThemeColor

    /// The default theme, used when the artwork has no usable colour.
    static let `default` = Theme(
        accent: .white,
        secondary: ThemeColor(red: 0.75, green: 0.86, blue: 1.0),
        backgroundDeep: ThemeColor(red: 0.02, green: 0.02, blue: 0.04),
        backgroundMid: ThemeColor(red: 0.08, green: 0.09, blue: 0.13)
    )

    /// The fixed theme, used when the user turns the artwork colours off.
    ///
    /// It is a soft blue rather than white, because white halos on a black
    /// background read as glare rather than as colour.
    static let `fixed` = Theme(
        accent: ThemeColor(red: 0.45, green: 0.68, blue: 1.0),
        secondary: ThemeColor(red: 0.62, green: 0.78, blue: 1.0),
        backgroundDeep: ThemeColor(red: 0.02, green: 0.03, blue: 0.06),
        backgroundMid: ThemeColor(red: 0.07, green: 0.10, blue: 0.16)
    )
}

/// Extracts a colour theme from album artwork.
///
/// The algorithm has five steps, each of them fixing a problem found by testing
/// against real covers:
///
/// 1. Downsample to 64x64.
/// 2. Discard pixels that are nearly white (max < 0.27) or nearly colourless
///    (saturation < 0.18). This is what the "most saturated pixel" approach
///    gets wrong: on a grey cover it picks white, which is invisible as a glow
///    and useless as text.
/// 3. If nothing survives, the artwork carries no usable colour — the theme
///    falls back to the default rather than inventing one.
/// 4. Cluster the survivors with k-means (k=3) and find the dominant hue with a
///    12-sector histogram.
/// 5. Assign the colours to roles and lift them so the text stays legible.
enum ArtworkPalette {

    /// Extracts the theme from an image.
    ///
    /// - Returns: the theme, or `nil` when the artwork has no usable colour.
    static func theme(from image: NSImage) -> Theme? {
        guard let pixels = downsample(image, side: 64) else { return nil }

        // Step 2: keep only pixels that carry colour.
        //
        // The channels are normalised to 0...1, so the brightness threshold is
        // 0.27 (which is 70/255). It used to be written as `70`, which no pixel
        // could ever reach — that is why every cover looked colourless.
        let colourful = pixels.filter { pixel in
            let maximum = max(pixel.red, pixel.green, pixel.blue)
            let minimum = min(pixel.red, pixel.green, pixel.blue)
            let saturation = maximum <= 0 ? 0 : (maximum - minimum) / maximum
            return maximum > 0.27 && saturation > 0.18
        }

        // Step 3: no colour means no theme.
        guard colourful.count >= 12 else {
            Log.line("palette: artwork has no usable colour, using the default theme")
            return nil
        }

        // Step 4: cluster and find the dominant hue.
        let clusters = kMeans(colourful, k: 3, iterations: 14)
        let dominant = dominantHue(colourful)

        // Step 5: assign roles.
        // The accent is the most colourful cluster; the backgrounds are the
        // darkest, so the text always has something to sit on.
        let sorted = clusters.sorted { saturation(of: $0) > saturation(of: $1) }
        let accentSource = dominant ?? sorted[0]
        let deepSource = clusters.min { luminance(of: $0) < luminance(of: $1) } ?? accentSource

        let accent = accentSource.brightened(to: 0.72)
        let secondary = (accentSource.blended(towards: .white, amount: 0.35)).brightened(to: 0.85)
        let backgroundDeep = deepSource.darkened(to: 0.18)
        var backgroundMid = accentSource.darkened(to: 0.30)

        // Guarantee legibility: the text has to contrast with the background.
        if accent.contrastRatio(against: backgroundMid) < 4.5 {
            backgroundMid = backgroundMid.darkened(to: 0.45)
        }

        let theme = Theme(
            accent: accent,
            secondary: secondary,
            backgroundDeep: backgroundDeep,
            backgroundMid: backgroundMid
        )

        Log.line("palette: accent \(accent.hex) secondary \(secondary.hex) bg \(backgroundMid.hex)")
        return theme
    }

    // MARK: - Sampling

    private struct Pixel {
        var red: Double
        var green: Double
        var blue: Double
    }

    /// Downsamples the image to a small square and reads its pixels.
    ///
    /// The drawing goes through a plain `CGContext` rather than through
    /// `NSBitmapImageRep` and `NSGraphicsContext`: the latter silently produces
    /// an all-black bitmap for a JPEG loaded from disk, which made every cover
    /// look like it had no colour at all.
    private static func downsample(_ image: NSImage, side: Int) -> [Pixel]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Log.line("palette: the artwork could not be read")
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &buffer,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var pixels: [Pixel] = []
        pixels.reserveCapacity(side * side)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            pixels.append(Pixel(
                red: Double(buffer[index]) / 255,
                green: Double(buffer[index + 1]) / 255,
                blue: Double(buffer[index + 2]) / 255
            ))
        }
        return pixels
    }

    // MARK: - Clustering

    /// k-means clustering over the RGB cube.
    private static func kMeans(_ pixels: [Pixel], k: Int, iterations: Int) -> [ThemeColor] {
        guard pixels.count >= k else { return [] }

        // Start from the most spread-out samples.
        var centroids: [ThemeColor] = [
            ThemeColor(red: pixels[0].red, green: pixels[0].green, blue: pixels[0].blue)
        ]
        while centroids.count < k {
            let candidate = pixels.max { lhs, rhs in
                distance(lhs, to: centroids) < distance(rhs, to: centroids)
            }
            guard let candidate else { break }
            centroids.append(ThemeColor(red: candidate.red, green: candidate.green, blue: candidate.blue))
        }

        for _ in 0..<iterations {
            var sums = [ThemeColor](repeating: ThemeColor(red: 0, green: 0, blue: 0), count: centroids.count)
            var counts = [Int](repeating: 0, count: centroids.count)

            for pixel in pixels {
                let colour = ThemeColor(red: pixel.red, green: pixel.green, blue: pixel.blue)
                var best = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (index, centroid) in centroids.enumerated() {
                    let d = squaredDistance(colour, centroid)
                    if d < bestDistance { bestDistance = d; best = index }
                }
                sums[best] = ThemeColor(
                    red: sums[best].red + colour.red,
                    green: sums[best].green + colour.green,
                    blue: sums[best].blue + colour.blue
                )
                counts[best] += 1
            }

            for index in centroids.indices where counts[index] > 0 {
                let count = Double(counts[index])
                centroids[index] = ThemeColor(
                    red: sums[index].red / count,
                    green: sums[index].green / count,
                    blue: sums[index].blue / count
                )
            }
        }

        return centroids
    }

    private static func squaredDistance(_ lhs: ThemeColor, _ rhs: ThemeColor) -> Double {
        let dr = lhs.red - rhs.red
        let dg = lhs.green - rhs.green
        let db = lhs.blue - rhs.blue
        return dr * dr + dg * dg + db * db
    }

    private static func distance(_ pixel: Pixel, to centroids: [ThemeColor]) -> Double {
        let colour = ThemeColor(red: pixel.red, green: pixel.green, blue: pixel.blue)
        return centroids.map { squaredDistance(colour, $0) }.min() ?? 0
    }

    // MARK: - Hue

    /// The dominant hue, as a 12-sector histogram.
    private static func dominantHue(_ pixels: [Pixel]) -> ThemeColor? {
        struct Sector {
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var count = 0
        }
        var sectors = [Sector](repeating: Sector(), count: 12)

        for pixel in pixels {
            let colour = ThemeColor(red: pixel.red, green: pixel.green, blue: pixel.blue)
            let maximum = max(colour.red, colour.green, colour.blue)
            let minimum = min(colour.red, colour.green, colour.blue)
            let delta = maximum - minimum
            guard delta > 0.001 else { continue }

            var hue: Double
            if maximum == colour.red {
                hue = (colour.green - colour.blue) / delta / 6
            } else if maximum == colour.green {
                hue = (colour.blue - colour.red) / delta / 6 + 2
            } else {
                hue = (colour.red - colour.green) / delta / 6 + 4
            }
            if hue < 0 { hue += 1 }

            let index = min(Int(hue * 12), 11)
            sectors[index].red += colour.red
            sectors[index].green += colour.green
            sectors[index].blue += colour.blue
            sectors[index].count += 1
        }

        guard let best = sectors.indices.max(by: { sectors[$0].count < sectors[$1].count }),
              sectors[best].count > 0
        else { return nil }

        let sector = sectors[best]
        let count = Double(sector.count)
        return ThemeColor(
            red: sector.red / count,
            green: sector.green / count,
            blue: sector.blue / count
        )
    }

    // MARK: - Helpers

    private static func saturation(of colour: ThemeColor) -> Double {
        let maximum = max(colour.red, colour.green, colour.blue)
        let minimum = min(colour.red, colour.green, colour.blue)
        return maximum <= 0 ? 0 : (maximum - minimum) / maximum
    }

    private static func luminance(of colour: ThemeColor) -> Double {
        colour.luminance
    }
}
