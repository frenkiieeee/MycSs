import Foundation
import Observation

/// Ready-made looks. Each one sets a handful of settings at once; the user can
/// then change any of them.
enum StylePreset: String, CaseIterable, Identifiable {
    case music, frenkiieeee, classic, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .frenkiieeee: return "Frenkiieeee"
        case .classic: return "Clásico"
        case .minimal: return "Minimal"
        }
    }

    var summary: String {
        switch self {
        case .music: return "Portada difuminada de fondo, reloj de cristal y líneas con profundidad, como Apple Music."
        case .frenkiieeee: return "Reloj grande en amarillo MycSs, resplandor de color y la mascota."
        case .classic: return "El aspecto original: reloj fino, resplandor y líneas planas."
        case .minimal: return "Solo la portada y la letra: sin reloj ni reproductor."
        }
    }

    func apply(to s: AppSettings) {
        // What every look shares.
        s.clockShowDate = true
        s.clockAlignment = .centre
        s.coverOnRight = false
        s.showClock = true
        s.showArtwork = true
        s.showTrackInfo = true
        s.showPlayerControls = true
        s.centerCoverWithoutLyrics = true

        switch self {
        case .music:
            s.backgroundMode = .cover
            s.lyricsDepth = true
            s.clockWeight = .light
            s.clockDesign = .rounded
            s.clockColor = .glass
            s.clockSize = 96

        case .frenkiieeee:
            s.backgroundMode = .glow
            s.lyricsDepth = true
            s.clockWeight = .heavy
            s.clockDesign = .rounded
            s.clockColor = .yellow
            s.clockSize = 112

        case .classic:
            s.backgroundMode = .glow
            s.lyricsDepth = false
            s.clockWeight = .light
            s.clockDesign = .rounded
            s.clockColor = .white
            s.clockSize = 104

        case .minimal:
            s.backgroundMode = .cover
            s.lyricsDepth = true
            s.showClock = false
            s.showPlayerControls = false
            s.clockWeight = .light
            s.clockDesign = .rounded
            s.clockColor = .white
            s.clockSize = 96
        }
    }
}

/// Ready-made looks for the notch: motion, indicators and colour at once.
enum NotchLook: String, CaseIterable, Identifiable {
    case sober, showy, quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sober: return "Sobrio"
        case .showy: return "Vistoso"
        case .quick: return "Rápido"
        }
    }

    var summary: String {
        switch self {
        case .sober: return "Se abre de golpe, cubierta cuadrada, barras blancas y solo el número al cambiar el volumen."
        case .showy: return "Elástica, a los lados primero, disco que gira, onda del color del álbum y anillo de volumen."
        case .quick: return "Respuesta inmediata, puntos amarillos y deslizador de volumen."
        }
    }

    func apply(to s: AppSettings) {
        switch self {
        case .sober:
            s.notchMotion = .smooth
            s.notchOpenStyle = .together
            s.notchPeekStyle = .drop
            s.notchVisualizerStyle = .bars
            s.notchHUDStyle = .minimal
            s.notchHUDNumber = .wheel
            s.notchHUDMotion = .smooth
            s.notchHUDEntrance = .fade
            s.notchAccent = .white
            s.notchCoverShape = .rounded
        case .showy:
            s.notchMotion = .bouncy
            s.notchOpenStyle = .sidesFirst
            s.notchPeekStyle = .sides
            s.notchVisualizerStyle = .wave
            s.notchHUDStyle = .ring
            s.notchHUDNumber = .counting
            s.notchHUDMotion = .elastic
            s.notchHUDEntrance = .pop
            s.notchAccent = .album
            s.notchCoverShape = .vinyl
        case .quick:
            s.notchMotion = .snappy
            s.notchOpenStyle = .together
            s.notchPeekStyle = .sides
            s.notchVisualizerStyle = .dots
            s.notchHUDStyle = .slider
            s.notchHUDNumber = .fixed
            s.notchHUDMotion = .glide
            s.notchHUDEntrance = .slide
            s.notchAccent = .yellow
            s.notchCoverShape = .rounded
        }
    }
}
