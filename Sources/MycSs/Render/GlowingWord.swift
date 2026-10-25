import SwiftUI

/// A word whose sung portion is lit.
///
/// The glow lives at the line level (see `LyricsView`), not here: masking a
/// blurred layer produces a hard edge at the mask boundary, which looks like a
/// smudge rather than like light. Keeping the glow behind the whole line and
/// the fill sweeping inside it is both cleaner and closer to how the reference
/// screenshots look.
struct GlowingWord: View {

    /// The text to draw.
    var text: String
    /// The colour of the lit part.
    var accent: Color
    /// The colour of the part that has not been sung yet.
    var inactive: Color
    /// How much of the word has been sung, from 0 to 1.
    var fill: Double
    /// The font.
    var font: Font

    var body: some View {
        ZStack(alignment: .leading) {
            // The part not yet sung.
            Text(text)
                .font(font)
                .foregroundStyle(inactive)

            // The part being sung.
            Text(text)
                .font(font)
                .foregroundStyle(accent)
                .mask(alignment: .leading) {
                    // The GeometryReader takes the size of the text it masks, so
                    // the fill is a fraction of the word's real width.
                    GeometryReader { geometry in
                        Rectangle()
                            .frame(width: geometry.size.width * fill)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .fixedSize()
    }
}
