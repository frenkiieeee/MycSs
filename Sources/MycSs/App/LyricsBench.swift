import Foundation

/// Measures how many songs get lyrics.
///
///     MycSs --lyrics-bench
///
/// It sends a fixed list of songs, written the way Spotify and Music report
/// them (with "feat.", "Remastered" and so on), through the real
/// `LyricsProvider`, and prints one line per song and the hit rate. It is the
/// way to know whether a change to the matching helped or only moved the
/// problem: run it before and after.
///
/// The list contains one instrumental on purpose, which is expected to miss.
enum LyricsBench {

    private struct Song {
        let title: String
        let artist: String
        let album: String
        let seconds: Double
    }

    private static let songs: [Song] = [
        Song(title: "Bohemian Rhapsody - Remastered 2011", artist: "Queen", album: "Bohemian Rhapsody (The Original Soundtrack)", seconds: 355),
        Song(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", seconds: 200),
        Song(title: "Shape of You", artist: "Ed Sheeran", album: "÷ (Deluxe)", seconds: 234),
        Song(title: "Tití Me Preguntó", artist: "Bad Bunny", album: "Un Verano Sin Ti", seconds: 243),
        Song(title: "BZRP Music Sessions, Vol. 52", artist: "Bizarrap, Quevedo", album: "BZRP Music Sessions, Vol. 52", seconds: 205),
        Song(title: "DESPECHÁ", artist: "ROSALÍA", album: "MOTOMAMI", seconds: 157),
        Song(title: "TQG", artist: "KAROL G, Shakira", album: "MAÑANA SERÁ BONITO", seconds: 200),
        Song(title: "Bailando - Spanish Version", artist: "Enrique Iglesias, Descemer Bueno, Gente De Zona", album: "SEX AND LOVE", seconds: 243),
        Song(title: "Dákiti", artist: "Bad Bunny, Jhay Cortez", album: "El Último Tour Del Mundo", seconds: 205),
        Song(title: "Hotel California - 2013 Remaster", artist: "Eagles", album: "Hotel California (2013 Remaster)", seconds: 391),
        Song(title: "Smells Like Teen Spirit", artist: "Nirvana", album: "Nevermind", seconds: 301),
        Song(title: "Rolling in the Deep", artist: "Adele", album: "21", seconds: 228),
        Song(title: "Someone Like You", artist: "Adele", album: "21", seconds: 285),
        Song(title: "Levitating (feat. DaBaby)", artist: "Dua Lipa", album: "Future Nostalgia", seconds: 203),
        Song(title: "Don't Start Now", artist: "Dua Lipa", album: "Future Nostalgia", seconds: 183),
        Song(title: "As It Was", artist: "Harry Styles", album: "Harry's House", seconds: 167),
        Song(title: "Flowers", artist: "Miley Cyrus", album: "Endless Summer Vacation", seconds: 200),
        Song(title: "Cruel Summer", artist: "Taylor Swift", album: "Lover", seconds: 178),
        Song(title: "Anti-Hero", artist: "Taylor Swift", album: "Midnights", seconds: 201),
        Song(title: "Mr. Brightside", artist: "The Killers", album: "Hot Fuss", seconds: 223),
        Song(title: "Take On Me", artist: "a-ha", album: "Hunting High and Low", seconds: 225),
        Song(title: "Dancing Queen", artist: "ABBA", album: "Arrival", seconds: 231),
        Song(title: "Billie Jean - Single Version", artist: "Michael Jackson", album: "Thriller 25 Super Deluxe Edition", seconds: 294),
        Song(title: "Lose Yourself", artist: "Eminem", album: "Curtain Call: The Hits", seconds: 326),
        Song(title: "DNA.", artist: "Kendrick Lamar", album: "DAMN.", seconds: 185),
        Song(title: "Yesterday - Remastered 2009", artist: "The Beatles", album: "1 (Remastered)", seconds: 126),
        Song(title: "Gangnam Style (강남스타일)", artist: "PSY", album: "PSY 6 (Six Rules), Part 1", seconds: 219),
        Song(title: "Dynamite", artist: "BTS", album: "Dynamite (DayTime Version)", seconds: 199),
        Song(title: "アイドル", artist: "YOASOBI", album: "アイドル", seconds: 213),
        Song(title: "Con Calma", artist: "Daddy Yankee, Snow", album: "Con Calma", seconds: 193),
        Song(title: "La Bachata", artist: "Manuel Turizo", album: "2000", seconds: 163),
        Song(title: "Ojitos Lindos", artist: "Bad Bunny, Bomba Estéreo", album: "Un Verano Sin Ti", seconds: 258),
        Song(title: "Vivir Mi Vida", artist: "Marc Anthony", album: "3.0", seconds: 254),
        Song(title: "Sweet Child O' Mine", artist: "Guns N' Roses", album: "Appetite For Destruction", seconds: 356),
        Song(title: "Where Is My Mind?", artist: "Pixies", album: "Surfer Rosa", seconds: 233),
        Song(title: "Nightcall", artist: "Kavinsky", album: "OutRun", seconds: 258),
        Song(title: "Apocalypse", artist: "Cigarettes After Sex", album: "Cigarettes After Sex", seconds: 290),
        Song(title: "Ella Baila Sola", artist: "Eslabon Armado, Peso Pluma", album: "DESVELADO", seconds: 166),
        // An instrumental: no lyrics exist, so a miss is the right answer.
        Song(title: "Experience", artist: "Ludovico Einaudi", album: "In a Time Lapse", seconds: 315),
    ]

    /// Songs that are harder to find: regional, older, indie and decorated.
    private static let hardSongs: [Song] = [
        Song(title: "Rata de Dos Patas", artist: "Paquita la del Barrio", album: "Taka Taka Ta", seconds: 213),
        Song(title: "El Rey", artist: "Vicente Fernández", album: "El Rey", seconds: 181),
        Song(title: "Garota de Ipanema", artist: "Stan Getz, João Gilberto, Antônio Carlos Jobim", album: "Getz/Gilberto", seconds: 321),
        Song(title: "Tum Hi Ho", artist: "Arijit Singh", album: "Aashiqui 2", seconds: 262),
        Song(title: "月亮代表我的心", artist: "邓丽君", album: "邓丽君精选", seconds: 213),
        Song(title: "Şımarık", artist: "Tarkan", album: "Ölürüm Sana", seconds: 227),
        Song(title: "La Vie en Rose", artist: "Édith Piaf", album: "La Vie en Rose", seconds: 186),
        Song(title: "Con te partirò", artist: "Andrea Bocelli", album: "Romanza", seconds: 245),
        Song(title: "99 Luftballons", artist: "Nena", album: "Nena", seconds: 233),
        Song(title: "Группа крови", artist: "Кино", album: "Группа крови", seconds: 285),
        Song(title: "Tusa", artist: "KAROL G, Nicki Minaj", album: "Tusa", seconds: 201),
        Song(title: "Pepas", artist: "Farruko", album: "Pepas", seconds: 287),
        Song(title: "La Camisa Negra", artist: "Juanes", album: "Mi Sangre", seconds: 217),
        Song(title: "Corazón Partío", artist: "Alejandro Sanz", album: "El Alma al Aire", seconds: 270),
        Song(title: "Mi Gente", artist: "J Balvin, Willy William", album: "Vibras", seconds: 189),
        Song(title: "Motion Sickness", artist: "Phoebe Bridgers", album: "Stranger in the Alps", seconds: 223),
        Song(title: "Holocene", artist: "Bon Iver", album: "Bon Iver", seconds: 337),
        Song(title: "Fade Into You", artist: "Mazzy Star", album: "So Tonight That I Might See", seconds: 296),
        Song(title: "Calm Down (with Selena Gomez)", artist: "Rema, Selena Gomez", album: "Rave & Roses", seconds: 239),
        Song(title: "STAY (with Justin Bieber)", artist: "The Kid LAROI, Justin Bieber", album: "F*CK LOVE 3: OVER YOU", seconds: 141),
        Song(title: "Sunflower - Spider-Man: Into the Spider-Verse", artist: "Post Malone, Swae Lee", album: "Spider-Man: Into the Spider-Verse", seconds: 158),
        Song(title: "Hype Boy", artist: "NewJeans", album: "NewJeans 1st EP 'New Jeans'", seconds: 179),
        Song(title: "Pretender", artist: "Official髭男dism", album: "Pretender", seconds: 326),
        Song(title: "Mamma Mia - 2008 Remaster", artist: "ABBA", album: "ABBA (Remastered)", seconds: 213),
        Song(title: "Ain't No Mountain High Enough", artist: "Marvin Gaye, Tammi Terrell", album: "United", seconds: 151),
        Song(title: "Ven Conmigo (Solita)", artist: "Dalex, Lenny Tavárez, Juhn", album: "Ven Conmigo", seconds: 220),
        Song(title: "Me Porto Bonito", artist: "Bad Bunny, Chencho Corleone", album: "Un Verano Sin Ti", seconds: 178),
        Song(title: "Yandel 150", artist: "Yandel, Feid", album: "Resistencia", seconds: 230),
    ]

    /// Asks the catalogues for the cover of every song, with no player involved.
    static func runCovers() async {
        let all = songs + hardSongs
        print("== Cover bench: \(all.count) songs (the catalogues only) ==")
        var hits = (itunes: 0, deezer: 0, none: 0)
        var rows = [String?](repeating: nil, count: all.count)
        var index = 0
        while index < all.count {
            let slice = Array(index..<min(index + 3, all.count))
            await withTaskGroup(of: (Int, String).self) { group in
                for i in slice {
                    let song = all[i]
                    group.addTask {
                        let started = Date()
                        guard let (_, image, origin) = await CoverProvider.shared.onlineCover(
                            title: song.title, artist: song.artist
                        ) else { return (i, "MISS  \(song.title)") }
                        return (i, String(format: "%-7@ %4.0fpx  %.1fs  %@", origin.rawValue as NSString,
                                          image.size.width, Date().timeIntervalSince(started), song.title as NSString))
                    }
                }
                for await (i, row) in group { rows[i] = row }
            }
            index += 3
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        for case let row? in rows {
            print("  \(row)")
            if row.hasPrefix("itunes") { hits.itunes += 1 } else if row.hasPrefix("deezer") { hits.deezer += 1 } else { hits.none += 1 }
        }
        print("\nitunes \(hits.itunes)  deezer (when iTunes missed) \(hits.deezer)  none \(hits.none)  of \(all.count)")
    }

    static func run() async {
        let args = CommandLine.arguments
        var all = args.contains("--hard") ? songs + hardSongs : songs
        if let option = args.first(where: { $0.hasPrefix("--limit=") }), let n = Int(option.dropFirst(8)) {
            all = Array(all.prefix(n))
        }
        if args.contains("--providers") {
            await runProviders(all)
            return
        }
        await runPipeline(all)
    }

    /// Asks each source on its own, to see what every one of them covers.
    private static func runProviders(_ list: [Song]) async {
        let parallel = Int(CommandLine.arguments.first { $0.hasPrefix("--parallel=") }?.dropFirst(11) ?? "3") ?? 3
        print("== Provider coverage: \(list.count) songs, \(parallel) at a time ==")
        print("   L = LRCLIB   N = NetEase line   W = NetEase word timing   Q = QQ Music\n")

        var rows = [(String, Bool, Bool, Bool, Bool)?](repeating: nil, count: list.count)
        var index = 0
        while index < list.count {
            let slice = Array(index..<min(index + parallel, list.count))
            await withTaskGroup(of: (Int, Bool, Bool, Bool, Bool).self) { group in
                for i in slice {
                    let song = list[i]
                    group.addTask {
                        var track = NowPlaying()
                        track.source = .spotify
                        track.title = song.title
                        track.artist = song.artist
                        track.album = song.album
                        track.durationSec = song.seconds
                        async let lrclib = LRCLib.fetch(for: track)
                        async let netease = NetEase.fetch(for: track)
                        async let qq = QQMusic.fetch(for: track)
                        let (l, n, q) = await (lrclib, netease, qq)
                        return (i, l != nil, n != nil && n!.wordTimingQuality != .real,
                                n?.wordTimingQuality == .real, q != nil)
                    }
                }
                for await (i, l, n, w, q) in group { rows[i] = (list[i].title, l, n, w, q) }
            }
            index += parallel
            if parallel == 1 {
                let pause = Double(CommandLine.arguments.first { $0.hasPrefix("--pause=") }?.dropFirst(8) ?? "1.5") ?? 1.5
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
        }

        var totals = (l: 0, n: 0, w: 0, q: 0, any: 0, withoutQQ: 0)
        for case let (title, l, n, w, q)? in rows {
            let marks = (l ? "L" : "-") + (n ? "N" : "-") + (w ? "W" : "-") + (q ? "Q" : "-")
            print("  \(marks)  \(title.prefix(60))")
            if l { totals.l += 1 }
            if n { totals.n += 1 }
            if w { totals.w += 1 }
            if q { totals.q += 1 }
            if l || n || w || q { totals.any += 1 }
            if l || n || w { totals.withoutQQ += 1 }
        }
        print("\nLRCLIB \(totals.l)  NetEase line \(totals.n)  NetEase word \(totals.w)  QQ \(totals.q)")
        print("with LRCLIB and NetEase only: \(totals.withoutQQ)/\(list.count)   with QQ Music too: \(totals.any)/\(list.count)")
    }

    private static func runPipeline(_ songs: [Song]) async {
        print("== Lyrics bench: \(songs.count) songs ==")
        let started = Date()

        var results = [(Song, Lyrics?, TimeInterval)?](repeating: nil, count: songs.count)
        // Six at a time: enough to be quick, little enough not to get blocked.
        let batch = 6
        var index = 0
        while index < songs.count {
            let slice = Array(index..<min(index + batch, songs.count))
            await withTaskGroup(of: (Int, Lyrics?, TimeInterval).self) { group in
                for i in slice {
                    let song = songs[i]
                    group.addTask {
                        var track = NowPlaying()
                        track.source = .spotify
                        track.title = song.title
                        track.artist = song.artist
                        track.album = song.album
                        track.durationSec = song.seconds
                        let t0 = Date()
                        let lyrics = await LyricsProvider.shared.lyrics(for: track, settle: 6)
                        return (i, lyrics, Date().timeIntervalSince(t0))
                    }
                }
                for await (i, lyrics, took) in group { results[i] = (songs[i], lyrics, took) }
            }
            index += batch
        }

        var hits = 0
        var bySource: [String: Int] = [:]
        var real = 0
        for case let (song, lyrics, took)? in results {
            if let lyrics {
                hits += 1
                bySource[lyrics.source.rawValue, default: 0] += 1
                if lyrics.wordTimingQuality == .real { real += 1 }
                print(String(format: "  OK   %-44@ %-10@ %@  %.1fs",
                             song.title.prefix(44) as NSString, lyrics.source.rawValue as NSString,
                             lyrics.wordTimingQuality == .real ? "word" : "line", took))
            } else {
                print(String(format: "  MISS %-44@ %@", song.title.prefix(44) as NSString, song.artist as NSString))
            }
        }
        print("\nhits: \(hits)/\(songs.count)  (word timing: \(real))  sources: \(bySource)")
        print(String(format: "total: %.1fs", Date().timeIntervalSince(started)))
    }
}
