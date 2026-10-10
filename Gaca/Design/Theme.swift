import SwiftUI

/// The Slate palette shared with the Android app (gaca-android ui/theme/Color.kt), plus
/// the few iOS-specific surfaces from the iPhone design canvas. Kept as named constants
/// because several are looked up by data (severity, crew), not by role.
enum Palette {
    static let page = Color(hex: "#F0F4F9")
    static let surface = Color.white
    static let accent = Color(hex: "#2D3C4C")
    static let onAccent = Color(hex: "#F4F9FE")
    static let textPrimary = Color(hex: "#282F35")
    static let textSecondary = Color(hex: "#5A6169")
    static let textMeta = Color(hex: "#747B83")
    static let chip = Color(hex: "#D8DFE6")
    static let field = Color(hex: "#E1E6EC")
    static let border = Color(hex: "#C8CED5")
    static let divider = Color(hex: "#D8DFE6")
    static let suggest = Color(hex: "#D7E3F0")
    static let onSuggest = Color(hex: "#22303D")
    static let activity = Color(hex: "#E3E8EE")
    static let destructive = Color(hex: "#B23A22")
    static let tabInactive = Color(hex: "#6A7178")
}

/// Severity is a closed set on the API (info | warn | urgent), so clients may switch on it.
struct SeverityStyle {
    let dot: Color
    let background: Color
    let ink: Color
    let label: String

    static func of(_ severity: String) -> SeverityStyle {
        switch severity {
        case "urgent":
            return SeverityStyle(dot: Color(hex: "#C55C43"), background: Color(hex: "#FBDDD5"), ink: Color(hex: "#A9462F"), label: "Urgent")
        case "warn":
            return SeverityStyle(dot: Color(hex: "#A9884F"), background: Color(hex: "#ECE1D0"), ink: Color(hex: "#7D6233"), label: "Heads up")
        default:
            return SeverityStyle(dot: Color(hex: "#8E99A4"), background: Color(hex: "#E3E8EE"), ink: Palette.textSecondary, label: "FYI")
        }
    }
}

/// A crew member's color comes over the wire as hex (CrewMemberOut.color) — the server
/// is the one source of truth for it; the client only derives display tints from it.
struct CrewStyle: Hashable {
    let color: Color
    /// A light wash for chips and pills.
    let tint: Color
    /// A darker shade of the color, readable as text on white or on the tint.
    let ink: Color
    /// The color itself, darkened enough to carry white text (buttons).
    let solid: Color

    init(hex: String?) {
        let base = RGB(hex: hex ?? "") ?? RGB(hex: "#2D3C4C")!
        color = base.color
        tint = base.mixed(with: .white, amount: 0.80).color
        ink = base.mixed(with: .black, amount: 0.25).color
        solid = base.mixed(with: .black, amount: 0.12).color
    }

    static let neutral = CrewStyle(hex: "#2D3C4C")
}

/// Two-letter initials for an avatar: "toolshed" → "To".
func crewInitials(_ name: String) -> String {
    let letters = name.filter { $0.isLetter || $0.isNumber }
    guard let first = letters.first else { return "?" }
    let second = letters.dropFirst().first.map { String($0).lowercased() } ?? ""
    return String(first).uppercased() + second
}

/// "toolshed" → "Toolshed" — crew names are lower-case slugs on the wire.
func crewDisplayName(_ name: String) -> String {
    name.prefix(1).uppercased() + name.dropFirst()
}

struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    func mixed(with other: RGB, amount t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

extension Color {
    init(hex: String) {
        self = (RGB(hex: hex) ?? .black).color
    }
}

extension Font {
    static let largeTitleGaca = Font.system(size: 34, weight: .bold)
    static let sectionLabel = Font.system(size: 13, weight: .semibold)
}
