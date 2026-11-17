import AppKit

/// The songs and covers of the demo mode (`--demo` and the settings previews).
enum DemoContent {

    /// A short song with lines of different lengths, so the layout and the
    /// scrolling can be seen.
    static let lrc = """
    [00:00.00] The first line of the demo song
    [00:03.00] A second line that is a little bit longer than the first one
    [00:06.00] Third
    [00:09.00] And this line is quite a lot longer, so that it has to wrap into more than one row of text
    [00:12.00] Short again
    [00:15.00] Another one
    [00:18.00] The last line of the first verse
    [00:21.00] The second verse begins right here
    [00:24.00] With a line that is long enough to wrap around the column of text
    [00:27.00] Almost done
    [00:30.00] The end
    """

    static let lrc2 = """
    [00:00.00] Another song begins, and the screen follows it
    [00:04.00] The cover changes first
    [00:07.00] Then the title
    [00:10.00] And the lyrics arrive from below, one line after the other, without a cut
    [00:14.00] Smooth
    [00:17.00] No jumps
    [00:20.00] Even when the song before had no lyrics at all
    [00:24.00] The column finds its place
    [00:28.00] Quietly
    [00:31.00] The end
    """

    /// A coloured square that stands in for an album cover in the demo.
    static func cover(variant: Int = 0) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let colors: [NSColor] = variant == 0
            ? [NSColor(red: 0.98, green: 0.36, blue: 0.22, alpha: 1),
               NSColor(red: 0.72, green: 0.12, blue: 0.45, alpha: 1),
               NSColor(red: 0.20, green: 0.10, blue: 0.55, alpha: 1)]
            : [NSColor(red: 0.10, green: 0.80, blue: 0.70, alpha: 1),
               NSColor(red: 0.08, green: 0.40, blue: 0.75, alpha: 1),
               NSColor(red: 0.05, green: 0.12, blue: 0.40, alpha: 1)]
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: -50)
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: NSRect(x: 150, y: 190, width: 300, height: 300)).fill()
            return true
        }
    }
}
