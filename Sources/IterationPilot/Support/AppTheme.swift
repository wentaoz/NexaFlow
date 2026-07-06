import AppKit
import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 8

    static var window: Color {
        dynamic(light: NSColor(hex: 0xFBF8F1), dark: NSColor(hex: 0x242424))
    }

    static var surface: Color {
        dynamic(light: NSColor(hex: 0xFBF8F1), dark: NSColor(hex: 0x242424))
    }

    static var panel: Color {
        dynamic(light: NSColor(hex: 0xF1ECE2), dark: NSColor(hex: 0x282828))
    }

    static var panelStrong: Color {
        dynamic(light: NSColor(hex: 0xE9E1D5), dark: NSColor(hex: 0x303030))
    }

    static var card: Color {
        dynamic(light: NSColor(hex: 0xFFFDF7), dark: NSColor(hex: 0x242424))
    }

    static var border: Color {
        dynamic(light: NSColor(hex: 0xD8D0C2), dark: NSColor(hex: 0x3A3A36))
    }

    static var divider: Color {
        dynamic(light: NSColor(hex: 0xE2DBCF), dark: NSColor(hex: 0x343430))
    }

    static var text: Color {
        dynamic(light: NSColor(hex: 0x2B2A27), dark: NSColor(hex: 0xF1EEE6))
    }

    static var mutedText: Color {
        dynamic(light: NSColor(hex: 0x746E64), dark: NSColor(hex: 0xB6AEA3))
    }

    static var faintText: Color {
        dynamic(light: NSColor(hex: 0x9A9388), dark: NSColor(hex: 0x8E8578))
    }

    static var icon: Color {
        dynamic(light: NSColor(hex: 0x6F695F), dark: NSColor(hex: 0xB2A99D))
    }

    static var accent: Color {
        dynamic(light: NSColor(hex: 0xC15F3C), dark: NSColor(hex: 0xD97757))
    }

    static var accentStrong: Color {
        dynamic(light: NSColor(hex: 0x9F442A), dark: NSColor(hex: 0xE89272))
    }

    static var accentSoft: Color {
        dynamic(light: NSColor(hex: 0xF1D8C9), dark: NSColor(hex: 0x33251F))
    }

    static var danger: Color {
        dynamic(light: NSColor(hex: 0xB64F43), dark: NSColor(hex: 0xE18478))
    }

    static var success: Color {
        dynamic(light: NSColor(hex: 0x6F7F4B), dark: NSColor(hex: 0xA8B47A))
    }

    static var warning: Color {
        dynamic(light: NSColor(hex: 0xB7793A), dark: NSColor(hex: 0xD8A15F))
    }

    static var info: Color {
        dynamic(light: NSColor(hex: 0x847A6D), dark: NSColor(hex: 0xB8AEA0))
    }

    static var shadow: Color {
        dynamic(light: NSColor(hex: 0x2B241D).withAlphaComponent(0.10), dark: NSColor.black.withAlphaComponent(0.22))
    }

    static var activeBackground: Color {
        accent.opacity(0.12)
    }

    static var hoverBackground: Color {
        panelStrong.opacity(0.72)
    }

    static func semanticTint(_ tint: AppSemanticTint) -> Color {
        switch tint {
        case .neutral: icon
        case .accent: accent
        case .success: success
        case .warning: warning
        case .danger: danger
        case .info: info
        }
    }

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

enum AppSemanticTint {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info
}

enum AppFont {
    static let textFamily = "Anthropic Serif Text"
    static let displayFamily = "Anthropic Serif Display"

    static func body(size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .custom(textFamily, size: size).weight(weight)
    }

    static func callout(weight: Font.Weight = .regular) -> Font {
        .custom(textFamily, size: 13).weight(weight)
    }

    static func caption(weight: Font.Weight = .regular) -> Font {
        .custom(textFamily, size: 12).weight(weight)
    }

    static func caption2(weight: Font.Weight = .regular) -> Font {
        .custom(textFamily, size: 11).weight(weight)
    }

    static func headline(weight: Font.Weight = .semibold) -> Font {
        .custom(textFamily, size: 15).weight(weight)
    }

    static func title(size: CGFloat = 22, weight: Font.Weight = .semibold) -> Font {
        .custom(displayFamily, size: size).weight(weight)
    }

    static func brand(size: CGFloat = 16, weight: Font.Weight = .semibold) -> Font {
        .custom(displayFamily, size: size).weight(weight)
    }
}

extension View {
    func appThemeRoot() -> some View {
        self
            .font(AppFont.body())
            .foregroundStyle(AppTheme.text)
            .tint(AppTheme.accent)
            .accentColor(AppTheme.accent)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
