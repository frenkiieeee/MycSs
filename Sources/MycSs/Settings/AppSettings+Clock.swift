import AppKit
import Foundation
import SwiftUI

/// The clock on the lyrics screen: look, size and when it hides.
extension AppSettings {

    // MARK: - Clock

    enum ClockWeight: String, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

        var weight: Font.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }

        var title: String {
            switch self {
            case .ultraLight: return "Ultrafina"
            case .thin: return "Fina"
            case .light: return "Ligera"
            case .regular: return "Normal"
            case .medium: return "Media"
            case .semibold: return "Seminegrita"
            case .bold: return "Negrita"
            case .heavy: return "Extranegrita"
            case .black: return "Black"
            }
        }
    }

    enum ClockDesign: String, CaseIterable {
        case standard, rounded, serif, monospaced

        var design: Font.Design {
            switch self {
            case .standard: return .default
            case .rounded: return .rounded
            case .serif: return .serif
            case .monospaced: return .monospaced
            }
        }

        var title: String {
            switch self {
            case .standard: return "SF Pro"
            case .rounded: return "SF Pro Rounded"
            case .serif: return "New York"
            case .monospaced: return "SF Mono"
            }
        }
    }

    enum ClockColor: String, CaseIterable {
        case white, glass, accent, yellow

        var title: String {
            switch self {
            case .white: return "Blanco"
            case .glass: return "Cristal"
            case .accent: return "Color del álbum"
            case .yellow: return "Amarillo MycSs"
            }
        }
    }

    enum ClockAlignment: String, CaseIterable {
        case centre, leading

        var title: String {
            switch self {
            case .centre: return "Centrado"
            case .leading: return "A la izquierda"
            }
        }
    }

    var clockWeight: ClockWeight {
        get { ClockWeight(rawValue: defaults.string(forKey: SettingKey.clockWeight) ?? "") ?? .light }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.clockWeight) }
    }

    var clockDesign: ClockDesign {
        get { ClockDesign(rawValue: defaults.string(forKey: SettingKey.clockDesign) ?? "") ?? .rounded }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.clockDesign) }
    }

    var clockColor: ClockColor {
        get { ClockColor(rawValue: defaults.string(forKey: SettingKey.clockColor) ?? "") ?? .white }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.clockColor) }
    }

    var clockAlignment: ClockAlignment {
        get { ClockAlignment(rawValue: defaults.string(forKey: SettingKey.clockAlignment) ?? "") ?? .centre }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.clockAlignment) }
    }

    /// The size of the time, in points. The date follows it.
    var clockSize: Double {
        get { min(max(defaults.object(forKey: SettingKey.clockSize) as? Double ?? 104, 48), 200) }
        set { defaults.set(newValue, forKey: SettingKey.clockSize) }
    }

    var clockShowDate: Bool {
        get { defaults.object(forKey: SettingKey.clockShowDate) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.clockShowDate) }
    }
}
