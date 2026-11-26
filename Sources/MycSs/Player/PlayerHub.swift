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
///
/// The user can also **move to the next player** that has something (the badge on
/// the cover, or the menu): in automatic mode that player is kept, even paused,
/// until it has nothing left or the user moves on; with a fixed preference the
/// preference itself changes.
final class PlayerHub: PlayerSource {

    /// Which player the user wants.
    enum Preference: String, CaseIterable {
        case automatic, spotify, appleMusic, browser

        var title: String {
            switch self {
            case .automatic: return "Automático"
            case .spotify: return "Spotify"
            case .appleMusic: return "Apple Music"
            case .browser: return "Navegador"
            }
        }

        var source: NowPlaying.Source? {
            switch self {
            case .automatic: return nil
            case .spotify: return .spotify
            case .appleMusic: return .appleMusic
            case .browser: return .browser
            }
        }
    }

    private let sources: [any PlayerSource]
    private let preference: () -> Preference

    private let lock = NSLock()
    private var activeID: NowPlaying.Source
    /// The player the user moved to, kept while it has something.
    private var pinnedID: NowPlaying.Source?
    /// What each player said the last time it was read.
    private var lastTitles: [NowPlaying.Source: String] = [:]

    init(
        sources: [any PlayerSource] = [SpotifySource(), AppleMusicSource(), BrowserSource()],
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

    /// A player that is no longer read has nothing to offer.
    private func forgetAllBut(_ ids: [NowPlaying.Source]) {
        lock.lock(); defer { lock.unlock() }
        lastTitles = lastTitles.filter { ids.contains($0.key) }
    }

    private func note(_ id: NowPlaying.Source, title: String) {
        lock.lock(); defer { lock.unlock() }
        lastTitles[id] = title
    }

    private var pinned: NowPlaying.Source? {
        lock.lock(); defer { lock.unlock() }
        return pinnedID
    }

    private func setPinned(_ id: NowPlaying.Source?) {
        lock.lock(); defer { lock.unlock() }
        pinnedID = id
    }

    // MARK: - PlayerSource

    func readPosition(completion: @escaping (PlayerSnapshot) -> Void) {
        let candidates = candidateSources()
        forgetAllBut(candidates.map(\.id))
        // A single candidate needs no comparison.
        if candidates.count == 1 {
            let only = candidates[0]
            setActive(only.id)
            only.readPosition { [self] snapshot in
                note(only.id, title: snapshot.title)
                completion(snapshot)
            }
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

    var availableSources: [NowPlaying.Source] {
        lock.lock(); defer { lock.unlock() }
        let order: [NowPlaying.Source] = [.spotify, .appleMusic, .browser]
        return order.filter { !(lastTitles[$0] ?? "").isEmpty }
    }

    @discardableResult
    func cycleSource() -> Bool {
        let current = id
        if let fixed = preference().source {
            // A fixed preference: the preference moves to the next player.
            var order: [NowPlaying.Source] = [.spotify, .appleMusic]
            if BrowserSource.isEnabled { order.append(.browser) }
            let index = order.firstIndex(of: fixed) ?? -1
            let next = order[(index + 1) % order.count]
            AppSettings.shared.playerPreference = Self.preference(for: next)
            Log.line("player: preference moved to \(next.rawValue)")
            return true
        }
        let available = availableSources
        guard let next = Self.next(after: current, in: available) else { return false }
        setPinned(next)
        setActive(next)
        Log.line("player: moved to \(next.rawValue)")
        return true
    }

    /// The player after `current` among those that have something, going round.
    static func next(after current: NowPlaying.Source, in available: [NowPlaying.Source]) -> NowPlaying.Source? {
        let others = available.filter { $0 != current }
        guard !others.isEmpty else { return nil }
        let order: [NowPlaying.Source] = [.spotify, .appleMusic, .browser]
        let start = order.firstIndex(of: current) ?? -1
        for step in 1...order.count {
            let candidate = order[(start + step) % order.count]
            if others.contains(candidate) { return candidate }
        }
        return others.first
    }

    private static func preference(for source: NowPlaying.Source) -> Preference {
        switch source {
        case .spotify: return .spotify
        case .appleMusic: return .appleMusic
        case .browser: return .browser
        case .none: return .automatic
        }
    }

    // MARK: - Choosing

    private func candidateSources() -> [any PlayerSource] {
        if let fixed = preference().source {
            return sources.filter { $0.id == fixed }
        }
        // The browser only when the user turned it on: asking it costs.
        return sources.filter { $0.id != .browser || BrowserSource.isEnabled }
    }

    private func read(
        _ candidates: [any PlayerSource],
        index: Int,
        collected: [(NowPlaying.Source, PlayerSnapshot)],
        completion: @escaping (PlayerSnapshot) -> Void
    ) {
        guard index < candidates.count else {
            for (source, snapshot) in collected { note(source, title: snapshot.title) }
            let (chosen, snapshot) = choose(from: collected, pinned: pinned)
            if let pinnedNow = pinned, chosen != pinnedNow { setPinned(nil) }
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
        from readings: [(NowPlaying.Source, PlayerSnapshot)],
        pinned: NowPlaying.Source?
    ) -> (NowPlaying.Source, PlayerSnapshot) {
        let current = id
        // The player the user moved to stays while it has something, even paused.
        if let pinned, let kept = readings.first(where: { $0.0 == pinned && !$0.1.title.isEmpty }) {
            return kept
        }
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
