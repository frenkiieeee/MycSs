import SwiftUI

/// The lyrics view: a stack of lines with the active one highlighted and the
/// active *word* filled in progressively.
///
/// The fill is driven by the interpolated playback position, so it advances
/// continuously inside a word rather than jumping from word to word. That
/// continuity is what makes it read as karaoke.
struct LyricsView: View {

    /// The lyrics to display.
    var lyrics: Lyrics?
    /// The interpolated playback position, in seconds.
    var position: TimeInterval
    /// The index of the active line.
    var activeIndex: Int?

    /// Colours come from the dynamic theme; these are the fallbacks.
    var activeColor: Color = .white
    var inactiveColor: Color = .white.opacity(0.3)

    /// The highlight style.
    var effect: AppSettings.LyricEffect = .word

    /// Font used for the lyrics.
    var font: Font = .system(size: 34, weight: .bold, design: .rounded)

    /// How many lines to show above and below the active one.
    var contextLines: Int = 3

    var body: some View {
        if let lyrics, !lyrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleIndices(in: lyrics), id: \.self) { index in
                    lineView(lyrics.lines[index], isActive: index == activeIndex)
                        .opacity(opacity(for: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Sin letras disponibles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Which lines to show

    /// The indices of the lines to display: the active one plus a window of
    /// lines around it.
    private func visibleIndices(in lyrics: Lyrics) -> [Int] {
        guard let activeIndex, activeIndex < lyrics.lines.count else {
            // Before the first line starts, show the opening lines.
            return Array(lyrics.lines.indices.prefix(contextLines + 1))
        }
        let lower = max(0, activeIndex - contextLines)
        let upper = min(lyrics.lines.count - 1, activeIndex + contextLines)
        return Array(lower...upper)
    }

    /// Lines further from the active one fade out.
    private func opacity(for index: Int) -> Double {
        guard let activeIndex else { return 0.6 }
        let distance = abs(index - activeIndex)
        if distance == 0 { return 1.0 }
        if distance == 1 { return 0.42 }
        if distance == 2 { return 0.22 }
        return 0.12
    }

    // MARK: - Line

    @ViewBuilder
    private func lineView(_ line: LyricLine, isActive: Bool) -> some View {
        if isActive, effect != .line, line.hasWordTiming {
            wordByWord(line)
        } else {
            Text(line.text)
                .font(font)
                .foregroundStyle(isActive ? activeColor : inactiveColor)
        }
    }

    /// Renders the active line word by word, filling each word as it is sung.
    ///
    /// The glow sits behind the whole line: a blurred copy of the text, added to
    /// the scene with `plusLighter` so it reads as light rather than as a
    /// shadow. The fill then sweeps through the words on top of it.
    private func wordByWord(_ line: LyricLine) -> some View {
        ZStack(alignment: .leading) {
            // The glow: the same text, blurred and added to the scene.
            Text(line.text)
                .font(font)
                .foregroundStyle(activeColor)
                .blur(radius: 22)
                .opacity(0.75)
                .blendMode(.plusLighter)

            HStack(spacing: 0) {
                ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                    if word.isBlank {
                        Text(" ")
                    } else {
                        GlowingWord(
                            text: word.text,
                            accent: activeColor,
                            inactive: inactiveColor,
                            fill: fillFraction(for: word),
                            font: font
                        )
                        // The fisheye effect: the word being sung is slightly
                        // larger, and its neighbours taper off. The change is
                        // continuous, so it reads as a swell rather than a jump.
                        .scaleEffect(fisheyeScale(for: word), anchor: .leading)
                    }
                }
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// How much of the word has been sung, as a fraction between 0 and 1.
    ///
    /// The word's own start and duration give the fraction; the duration is
    /// estimated when the source only had line-level timings.
    private func fillFraction(for word: LyricWord) -> Double {
        let duration = word.duration > 0 ? word.duration : 0.4
        let elapsed = position - word.startTime
        guard elapsed > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    /// The scale of a word in the fisheye effect.
    ///
    /// The word being sung swells as the singing progresses through it. The
    /// curve is a smoothstep rather than a sine, because a sine starts and ends
    /// abruptly at the extremes while a smoothstep has no sudden change of
    /// direction.
    private func fisheyeScale(for word: LyricWord) -> Double {
        guard effect == .fisheye else { return 1.0 }
        let fraction = fillFraction(for: word)

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
