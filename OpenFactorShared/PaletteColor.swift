import SwiftUI

/// One colour, as plain sRGB numbers.
///
/// Deliberately not a SwiftUI `Color`. A `Color` cannot be inspected, so a palette built
/// from them can only be checked by looking at it, and "we looked at it" is not something
/// a reviewer can verify or a test can enforce. These are components, so the contrast of
/// every entry against the text drawn on it is computed and asserted in the test suite.
struct PaletteColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From a hex literal, which is how the palette below is written, because six hex
    /// digits are easier to compare against a design than three decimals.
    init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    /// Relative luminance, per the WCAG 2.1 definition.
    ///
    /// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Contrast ratio against another colour, from 1 (identical) to 21 (black on white).
    ///
    /// https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio
    func contrastRatio(against other: PaletteColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)

        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Moves a colour toward black, for the darker end of a card's gradient.
    func darkened(by amount: Double) -> PaletteColor {
        PaletteColor(red * (1 - amount), green * (1 - amount), blue * (1 - amount))
    }

    static let white = PaletteColor(1, 1, 1)
}
