import Foundation

/// Chooses which player to read.
///
/// In **automatic** mode it looks at every player and follows the one that is
/// playing. It sticks to the player it was already following as long as that one
/// keeps playing, so two players open at once do not make the lyrics flip back
/// and forth. A fixed preference reads that player and nothing else.
///
/// The players are read **one after the other, never at the same time**:
/// `NSAppleScript` is not thread-safe, and each source runs its scripts on its
/// own queue, so overlapping readings could overlap Apple Events.
final class PlayerHub: PlayerSource {

    /// Which player the user wants.
    enum Preference: String, CaseIterable {
        case automatic, spotify, appleMusic

        var title: String {
            switch self {
            case .automatic: return "Automático"
            case .spotify: return "Spotify"
            case .appleMusic: return "Apple Music"
            }
        }
    }

    private let sources: [any PlayerSource]
    private let preference: () -> Preference

    private let lock = NSLock()
    private var activeID: NowPlaying.Source

    init(
        sources: [any PlayerSource] = [SpotifySource(), AppleMusicSource()],
        preference: @escaping () -> Preference = { AppSettings.shared.playerPreference }
    ) {
        self.sources = sources
        self.preference = preference
        self.activeID = sources.first?.id ?? .none
    }

    /// The player being followed right now.
    var id: NowPlaying.Source {
        lock.lock(); defer { lock.unlock() }
        return activeID
    }

    private var active: any PlayerSource {
        let current = id
        return sources.first { $0.id == current } ?? sources[0]
    }

    private func setActive(_ id: NowPlaying.Source) {
        lock.lock(); defer { lock.unlock() }
        activeID = id
    }

    // MARK: - PlayerSource

    func readPosition(completion: @escaping (PlayerSnapshot) -> Void) {
        let candidates = candidateSources()
        // A single candidate needs no comparison.
        if candidates.count == 1 {
            setActive(candidates[0].id)
            candidates[0].readPosition(completion: completion)
            return
        }
        read(candidates, index: 0, collected: [], completion: completion)
    }

    func readTrack(completion: @escaping (PlayerTrackMetadata) -> Void) {
        active.readTrack(completion: completion)
    }

    func artworkURL() -> String? { active.artworkURL() }

    func artworkData() -> Data? { active.artworkData() }

    func send(_ command: PlayerCommand) { active.send(command) }

    // MARK: - Choosing

    private func candidateSources() -> [any PlayerSource] {
        switch preference() {
        case .automatic: return sources
        case .spotify: return sources.filter { $0.id == .spotify }
        case .appleMusic: return sources.filter { $0.id == .appleMusic }
        }
    }

    private func read(
        _ candidates: [any PlayerSource],
        index: Int,
        collected: [(NowPlaying.Source, PlayerSnapshot)],
        completion: @escaping (PlayerSnapshot) -> Void
    ) {
        guard index < candidates.count else {
            let (chosen, snapshot) = choose(from: collected)
            setActive(chosen)
            completion(snapshot)
            return
        }
        candidates[index].readPosition { [self] snapshot in
            read(
                candidates,
                index: index + 1,
                collected: collected + [(candidates[index].id, snapshot)],
                completion: completion
            )
        }
    }

    private func choose(
        from readings: [(NowPlaying.Source, PlayerSnapshot)]
    ) -> (NowPlaying.Source, PlayerSnapshot) {
        let current = id
        let playing = readings.filter { $0.1.isPlaying }

        // Keep following the current player while it is still playing.
        if let kept = playing.first(where: { $0.0 == current }) { return kept }
        // Otherwise the first one that is playing.
        if let first = playing.first { return first }
        // Nobody is playing: stay on the current one if it still has a track
        // (paused), or move to any player that has one.
        if let kept = readings.first(where: { $0.0 == current && !$0.1.title.isEmpty }) { return kept }
        if let any = readings.first(where: { !$0.1.title.isEmpty }) { return any }
        return readings.first(where: { $0.0 == current }) ?? readings[0]
    }
}
