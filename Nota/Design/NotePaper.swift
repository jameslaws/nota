import SwiftUI

/// The paper colours. Muted rather than fluorescent — a real post-it is dye on
/// paper, not a saturated screen colour, and six of those on a desktop is a mess.
/// Each carries its own ink so text stays legible on every sheet, in both appearances.
enum NotePaper: String, CaseIterable, Identifiable, Sendable {
    case butter
    case apricot
    case rose
    case mint
    case sky
    case lilac
    case slate

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    /// Top and bottom of a very slight vertical wash, which reads as paper rather
    /// than a flat rectangle.
    var top: Color {
        switch self {
        case .butter: Color(light: 0xFFF2B8, dark: 0x5A4E1E)
        case .apricot: Color(light: 0xFFDCB8, dark: 0x5C3F22)
        case .rose: Color(light: 0xFFD3DA, dark: 0x5C2C36)
        case .mint: Color(light: 0xC8EFD4, dark: 0x1F4A32)
        case .sky: Color(light: 0xCBE4FB, dark: 0x22415C)
        case .lilac: Color(light: 0xDED8FB, dark: 0x3A3260)
        case .slate: Color(light: 0xE6E8EC, dark: 0x33383F)
        }
    }

    var bottom: Color {
        switch self {
        case .butter: Color(light: 0xFFE88F, dark: 0x4C4218)
        case .apricot: Color(light: 0xFFCB97, dark: 0x4E341B)
        case .rose: Color(light: 0xFFBDC8, dark: 0x4E242D)
        case .mint: Color(light: 0xAEE7C0, dark: 0x183E29)
        case .sky: Color(light: 0xB2D7F8, dark: 0x1B364D)
        case .lilac: Color(light: 0xCDC4F9, dark: 0x302952)
        case .slate: Color(light: 0xD8DBE1, dark: 0x2A2F35)
        }
    }

    var ink: Color {
        switch self {
        case .slate: Color(light: 0x1F2328, dark: 0xF2F4F7)
        default: Color(light: 0x3A2E12, dark: 0xF6F1E4)
        }
    }

    var inkSoft: Color { ink.opacity(0.55) }

    /// The swatch shown in the colour row.
    var swatch: Color { bottom }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
