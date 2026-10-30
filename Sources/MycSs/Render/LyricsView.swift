import Observation
import SwiftUI

/// The lyrics view: a stack of lines with the active one highlighted and the
/// active *word* filled in progressively.
///
/// The fill is driven by the interpolated playback position, so it advances
/// continuously inside a word rather than jumping from word to word. That
/// continuity is what makes it read as karaoke.
///
/// **How a line moves when the song does**: the lyrics are a tall column that
/// slides up and down, and the active line is kept in the middle of the
/// screen. The next line arrives from below and the previous one leaves at the
/// top. The movement is a translation, never a fade or a blur, so the eye can
/// follow the text instead of losing it.
///
/// **Why the movement is done by hand**: SwiftUI's own `scrollPosition` and
/// `scrollTo` do nothing on this system — the offset of the scroll view stays
/// where it is — so the column is moved with an offset instead. The offset is
/// worked out from the height of each line, which is measured as the lines are
/// laid out.
///
/// Two details make the movement smooth:
///
/// * **Every line is always in the column.** Rendering only a window around
///   the active line would insert and remove views while the song plays, and
///   each insertion shifts the content under the reader.
/// * **A line looks the same whether it is active or not.** The karaoke words
///   measure exactly like the plain ones, so a line does not change height
///   when it becomes the active one.
struct LyricsView: View {

    /// The state of the column.
    ///
    /// It lives in an `@Observable` object rather than in `@State`, because the
    /// Command Line Tools do not ship the SwiftUI macros plugin that `@State`
    /// needs.
    @Bindable var layout = LyricsLayout.shared

    /// How the active line is highlighted.
    enum Effect {
        /// The whole line is lit.
        case line
        /// The word being sung fills in progressively.
        case word
        /// The word being sung swells, its neighbours taper off.
        case fisheye
    }

    /// The lyrics to display.
    var lyrics: Lyrics?
    /// The index of the active line.
    var activeIndex: Int?

    /// The model, used by the active line only.
    ///
    /// The active line reads the position from the model by itself, so that the
    /// column of seventy lines is not rebuilt sixty times a second: only the
    /// line that is being sung is.
    @Bindable var model: LyricsViewModel

    /// The colour of the text that has not been sung yet.
    var inactiveColor: Color = .white.opacity(0.42)

    /// The highlight style.
    var effect: AppSettings.LyricEffect = .word

    /// Font used for the lyrics.
    var font: Font = .system(size: 38, weight: .bold)

    var body: some View {
        if let lyrics, !lyrics.isEmpty {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    lines(lyrics)
                        // The room above and below the lines, so that the first
                        // and the last one can be in the middle as well.
                        .padding(.vertical, geometry.size.height / 2)
                        // Room on the sides for the halo of the first and
                        // the last word: the halo of a line reaches about
                        // twenty points past the letters, and if the block
                        // ends there it is cut in a straight line.
                        .padding(.horizontal, 26)
                }
                .offset(y: -layout.offset)
            }
            // The letters fade in at the top and fade out at the bottom,
            // instead of being cut off by the edge of the block.
            //
            // The mask is on the reader and not on the column, because the
            // column is as tall as the whole song: the gradient has to be the
            // height of the part of it that is on screen.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.3), location: 0.05),
                        .init(color: .white.opacity(0.65), location: 0.1),
                        .init(color: .white.opacity(0.88), location: 0.15),
                        .init(color: .white, location: 0.21),
                        .init(color: .white, location: 0.79),
                        .init(color: .white.opacity(0.88), location: 0.85),
                        .init(color: .white.opacity(0.65), location: 0.9),
                        .init(color: .white.opacity(0.3), location: 0.95),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onPreferenceChange(LineHeightKey.self) { heights in
                // The heights only change when the text or the width changes.
                // Working the offset out again on every measurement would
                // interrupt the movement of the column, which is what makes it
                // look mechanical.
                guard heights != layout.heights else { return }
                layout.heights = heights
                layout.move(to: layout.target)
            }
            .onChange(of: activeIndex) { _, newValue in
                // The column follows the song.
                layout.target = newValue
                layout.move(to: newValue)
            }
            .onAppear {
                layout.move(to: activeIndex)
            }
        } else {
            Text("Sin letras disponibles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - The column of lines

    /// Every line of the lyrics, one after the other.
    private func lines(_ lyrics: Lyrics) -> some View {
        VStack(alignment: .leading, spacing: LyricsLayout.spacing) {
            ForEach(Array(lyrics.lines.indices), id: \.self) { index in
                if index == activeIndex {
                    ActiveLine(
                        line: lyrics.lines[index],
                        index: index,
                        model: model,
                        inactiveColor: inactiveColor,
                        effect: effect,
                        font: font
                    )
                } else {
                    QuietLine(
                        line: lyrics.lines[index],
                        index: index,
                        inactiveColor: inactiveColor,
                        effect: effect,
                        font: font
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Line

    /// A line that is not being sung.
    ///
    /// It is drawn with the same word flow as the active one, so that a line
    /// keeps its height when the song moves on to it.
    private struct QuietLine: View {
        var line: LyricLine
        var index: Int
        var inactiveColor: Color
        var effect: AppSettings.LyricEffect
        var font: Font

        var body: some View {
            LyricsLine(
                line: line,
                index: index,
                accent: .white,
                inactive: inactiveColor,
                // The mask stays open on the lines that are not being sung, so
                // that the fade of the line that was being sung is visible: if
                // the mask closed at the same time, the white would vanish in
                // one frame and the change of line would look like a cut.
                fill: { _ in 1 },
                effect: effect,
                font: font,
                position: 0,
                swells: false,
                highlight: 0
            )
        }
    }

    /// The line that is being sung.
    ///
    /// It reads the position from the model, so it is the only part of the
    /// lyrics that is rebuilt while the song plays.
    private struct ActiveLine: View {
        var line: LyricLine
        var index: Int
        @Bindable var model: LyricsViewModel
        var inactiveColor: Color
        var effect: AppSettings.LyricEffect
        var font: Font

        var body: some View {
            LyricsLine(
                line: line,
                index: index,
                accent: .white,
                inactive: inactiveColor,
                fill: { word in
                    let duration = word.duration > 0 ? word.duration : 0.4
                    let elapsed = model.position - word.startTime
                    guard elapsed > 0 else { return 0 }
                    return min(max(elapsed / duration, 0), 1)
                },
                effect: effect,
                font: font,
                position: model.position,
                swells: true,
                highlight: 1
            )
            // The halo: a shadow of the line, in white. A shadow is drawn
            // around the letters by the graphics system, so it is not cut at
            // the edge of the view the way a blurred copy is.
            .shadow(color: .white.opacity(0.34), radius: 14)
        }
    }

    /// A line of lyrics, drawn word by word.
    private struct LyricsLine: View {
        var line: LyricLine
        /// The position of the line in the song, used to measure it.
        var index: Int
        var accent: Color
        var inactive: Color
        var fill: (LyricWord) -> Double
        var effect: AppSettings.LyricEffect
        var font: Font
        /// The position of the song, for the fisheye effect.
        var position: TimeInterval
        /// Whether the words of this line swell.
        var swells: Bool
        /// How lit the line is: 1 while it is being sung, 0 in the others.
        var highlight: Double

        var body: some View {
            WrappingHStack(spacing: 0, lineSpacing: 8) {
                ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                    // The word is drawn with its own trailing space: that space
                    // is part of the word's own width, and trimming it away
                    // would run the words together ("diamantesdeboda").
                    GlowingWord(
                        text: word.text,
                        accent: accent,
                        inactive: inactive,
                        fill: fill(word),
                        font: font,
                        highlight: highlight
                    )
                    // The fisheye effect: the word being sung is slightly
                    // larger, and its neighbours taper off. The change is
                    // continuous, so it reads as a swell rather than a jump.
                    .scaleEffect(fisheyeScale(for: word), anchor: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The height of the line, so that the column knows how far it has
            // to move to bring a line into the middle.
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: LineHeightKey.self, value: [index: proxy.size.height])
                }
            }
        }

        /// The scale of a word in the fisheye effect.
        ///
        /// The word being sung swells while it is being sung, in the same
        /// continuous way as the fill, so it reads as a swell rather than a
        /// jump.
        private func fisheyeScale(for word: LyricWord) -> CGFloat {
            guard effect == .fisheye, swells else { return 1.0 }
            let fraction = fill(word)

            // Words that have not started yet shrink slightly as they approach.
            if fraction <= 0 {
                let untilStart = word.startTime - position
                guard untilStart < 2.0 else { return 0.96 }
                // Smoothly ramps from 0.90 to 0.96 as the word approaches.
                let approach = 1.0 - min(untilStart / 2.0, 1.0)
                return 0.90 + smoothstep(approach) * 0.06
            }

            // The word being sung swells up and settles back.
            let swell = smoothstep(fraction)
            return 0.96 + swell * 0.14
        }

        /// Smoothstep: a curve with no sudden change of direction at the ends.
        private func smoothstep(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
    }
}

/// The state of the column of lyrics.
///
/// It lives in an `@Observable` object rather than in `@State`, because the
/// Command Line Tools do not ship the SwiftUI macros plugin that `@State`
/// needs.
@Observable
final class LyricsLayout {

    /// Shared, because the view is rebuilt on every frame and a per-view state
    /// would be lost each time.
    static let shared = LyricsLayout()

    /// The gap between two lines.
    static let spacing: CGFloat = 14

    /// The line the column is centred on.
    var target: Int?

    /// The height of each line, measured as the lines are laid out.
    var heights: [Int: CGFloat] = [:]

    /// How far the column is moved up, so that the active line is in the
    /// middle of the screen.
    var offset: CGFloat = 0

    /// Moves the column so that the given line is in the middle.
    ///
    /// The distance is the height of the lines above it plus half of its own
    /// height. The room above and below the lines is already there, so the
    /// first and the last line can be in the middle as well.
    ///
    /// **The line has to be measured first**: the height of the line that is
    /// just starting is not known until it has been laid out, and moving the
    /// column with a guess would start the movement in the wrong place and
    /// then jump to the right one when the measurement arrives. That jump is
    /// what makes the change of line look mechanical.
    func move(to index: Int?) {
        target = index
        guard let index, heights[index] != nil else { return }

        var distance: CGFloat = 0
        for line in 0..<index {
            distance += (heights[line] ?? 0) + Self.spacing
        }
        distance += (heights[index] ?? 0) / 2

        // The movement is a spring: it slows down as it arrives instead of
        // stopping dead, which is what makes the change of line look like the
        // text is being carried rather than being teleported.
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            offset = distance
        }
    }
}

/// The height of each line of the lyrics.
struct LineHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
