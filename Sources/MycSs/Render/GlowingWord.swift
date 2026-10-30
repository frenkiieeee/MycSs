import SwiftUI

/// A word whose sung portion is lit.
///
/// The word is drawn twice: once in the colour of the part that has not been
/// sung yet, and once in the colour of the part that is being sung, masked so
/// that only the sung part shows. The mask is a fraction of the word's width,
/// so the fill advances smoothly inside the word.
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

    /// How lit the word is, from 0 to 1.
    ///
    /// It is 1 in the line that is being sung and 0 in the others. The change
    /// is animated, so the line that was being sung fades out as the column
    /// moves, instead of going out all at once.
    var highlight: Double = 1

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
                .opacity(highlight)
                // The fade of the line that was being sung.
                //
                // It is attached to the text and not to the line, so that only
                // the colour fades: the mask below has to follow the song
                // exactly, and an animated mask would sweep the words backwards.
                .animation(.easeOut(duration: 0.35), value: highlight)
                .mask {
                    GeometryReader { geometry in
                        // The GeometryReader takes the size of the text it
                        // masks, so the fill is a fraction of the word's real
                        // width.
                        Rectangle()
                            .frame(width: geometry.size.width * fill)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // The fill follows the song, and a song does not
                            // wait for an animation to finish.
                            .transaction { $0.animation = nil }
                    }
                }
        }
        // The word takes exactly the width of its text: no padding, so the
        // layout can place the spaces between the words itself.
        .fixedSize()
    }
}
