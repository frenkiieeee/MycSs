import Foundation

/// What the page script finds in a browser tab: the media that plays and the page's
/// best icon. Parsed from the JSON the script returns (spec 014).
struct BrowserMedia: Equatable {
    var isPlaying: Bool
    var position: Double
    var duration: Double
    var title: String
    var artist: String
    var album: String
    /// The site, `www.youtube.com` written as `youtube.com`.
    var host: String
    /// The largest icon the page declares, or its `/favicon.ico`.
    var iconURL: String
    var pageURL: String

    /// The script returns an empty string when the tab has nothing playing, and
    /// anything else that is not this JSON means a broken answer: both are nil.
    static func parse(_ text: String) -> BrowserMedia? {
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = (object["ti"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = Self.siteName(object["h"] as? String ?? "")
        guard !title.isEmpty || !host.isEmpty else { return nil }
        return BrowserMedia(
            isPlaying: object["p"] as? Bool ?? false,
            position: Self.number(object["t"]),
            duration: Self.number(object["d"]),
            title: title.isEmpty ? host : title,
            artist: (object["ar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            album: (object["al"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            host: host,
            iconURL: object["i"] as? String ?? "",
            pageURL: object["u"] as? String ?? ""
        )
    }

    private static func number(_ value: Any?) -> Double {
        let raw = (value as? NSNumber)?.doubleValue ?? 0
        return raw.isFinite ? max(raw, 0) : 0
    }

    static func siteName(_ host: String) -> String {
        var name = host.lowercased()
        for prefix in ["www.", "m.", "music.", "open."] where name.hasPrefix(prefix) && name.count > prefix.count + 3 {
            name = String(name.dropFirst(prefix.count))
        }
        return name
    }

    // MARK: - The scripts

    /// Finds the media of the page: the first `<video>` or `<audio>` that plays with
    /// sound, or else one that was started and is paused; and Media Session's
    /// title, artist and album. Returns "" when the page has nothing.
    ///
    /// Written with single quotes only, so it can be put in an AppleScript string as
    /// it is (see `appleScriptLiteral`).
    static let readScript = """
    (function(){try{\
    var ms=[].slice.call(document.querySelectorAll('video,audio'));var m=null;\
    for(var i=0;i<ms.length;i++){var e=ms[i];if(!e.paused&&!e.ended&&e.readyState>2&&!e.muted&&e.volume>0){m=e;break;}}\
    if(!m){for(var j=0;j<ms.length;j++){var f=ms[j];if(f.currentTime>0&&!f.ended&&f.duration>1&&!f.muted){m=f;break;}}}\
    var md=navigator.mediaSession&&navigator.mediaSession.metadata;\
    var st=navigator.mediaSession?navigator.mediaSession.playbackState:'none';\
    if(!m&&!(md&&st==='playing'))return '';\
    var ic='',best=0;var ls=document.querySelectorAll('link[rel~=icon],link[rel=apple-touch-icon],link[rel=apple-touch-icon-precomposed]');\
    for(var k=0;k<ls.length;k++){var l=ls[k];var sz=parseInt((l.getAttribute('sizes')||'').split('x')[0])||(l.rel.indexOf('apple')>=0?180:32);\
    if(sz>best&&l.href){best=sz;ic=l.href;}}\
    return JSON.stringify({p:m?!m.paused:st==='playing',t:m?m.currentTime:0,d:m&&isFinite(m.duration)?m.duration:0,\
    ti:(md&&md.title)||document.title,ar:(md&&md.artist)||'',al:(md&&md.album)||'',h:location.hostname,\
    i:ic||(location.origin+'/favicon.ico'),u:location.href});\
    }catch(x){return '';}})()
    """

    /// The script of a command. The media element when there is one; for the next
    /// and previous song, the page's own buttons (YouTube, SoundCloud, Spotify web
    /// and anything labelled so), and else back to the start.
    static func commandScript(_ command: PlayerCommand) -> String {
        let pick = "var ms=[].slice.call(document.querySelectorAll('video,audio'));"
            + "var m=ms.filter(function(e){return !e.paused&&!e.muted;})[0]||ms.filter(function(e){return e.currentTime>0;})[0]||null;"
        // `before` runs first (for play and pause, the element itself: a page's button
        // can be the wrong one), then the page's button, then `after`.
        func script(before: String = "", buttons: String, after: String = "") -> String {
            "(function(){\(pick)\(before)var b=document.querySelector('\(buttons)');if(b){b.click();return 'ok';}\(after)return '';})()"
        }
        switch command {
        case .playPause:
            return script(
                before: "if(m){if(m.paused){m.play();}else{m.pause();}return 'ok';}",
                buttons: ".ytp-play-button,[data-testid=control-button-playpause],.playControl"
            )
        case .next:
            return script(
                buttons: ".ytp-next-button,[data-testid=control-button-skip-forward],.skipControl__next,[aria-label=Next],[aria-label=Siguiente]"
            )
        case .previous:
            return script(
                buttons: ".ytp-prev-button,[data-testid=control-button-skip-back],.skipControl__previous,[aria-label=Previous],[aria-label=Anterior]",
                after: "if(m){m.currentTime=0;return 'ok';}"
            )
        case .seek(let seconds):
            let target = String(format: "%.2f", max(0, seconds))
            return "(function(){\(pick)if(m){m.currentTime=\(target);return 'ok';}return '';})()"
        }
    }

    /// A script as an AppleScript string literal.
    static func appleScriptLiteral(_ script: String) -> String {
        "\"" + script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
