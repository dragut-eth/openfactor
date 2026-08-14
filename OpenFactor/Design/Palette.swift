import OpenFactorCore
import SwiftUI

/// The colours a card can be drawn in.
///
/// `AccountColor` in the core is a name and nothing else. This is where a name becomes a
/// colour, which means a palette change never touches stored data and stored data never
/// pins a palette.
///
/// ## Why these are darker than the app that inspired them
///
/// Every card carries white text, including the code itself, so every entry has to be
/// dark enough for white to be legible on it. WCAG asks for a contrast ratio of 4.5 to 1
/// for body text, and `PaletteTests` asserts that every entry clears it, in both colour
/// schemes and at both ends of the gradient. That rules out the bright yellows and light
/// oranges an authenticator would otherwise reach for, and it is why the palette here is
/// deeper than Step Two's.
///
/// This is not a design preference. A code that cannot be read at arm's length in
/// sunlight is a broken feature in an app whose entire job is showing you six digits.
enum Palette {

    /// The two variants of one palette entry.
    ///
    /// The difference between them is small on purpose. Both have to stay dark enough for
    /// white text, so a light scheme variant cannot simply be a brighter version. What it
    /// gets instead is a little more depth, which keeps the card's edge crisp against a
    /// white background rather than glowing into it.
    struct Entry: Sendable, Equatable {
        let dark: PaletteColor
        let light: PaletteColor

        func base(for scheme: ColorScheme) -> PaletteColor {
            scheme == .dark ? self.dark : self.light
        }
    }

    /// How far the bottom of a card's gradient is darkened from its base.
    ///
    /// Darkening rather than lightening matters: it can only increase contrast against
    /// white text, so the base colour is always the worst case and the tests only have to
    /// prove the base and this one derived stop.
    static let gradientDepth = 0.18

    static let entries: [AccountColor: Entry] = [
        .red: Entry(dark: PaletteColor(hex: 0xC6_2828), light: PaletteColor(hex: 0xB3_251F)),
        .orange: Entry(dark: PaletteColor(hex: 0xBE_4E00), light: PaletteColor(hex: 0xB0_4A00)),
        .yellow: Entry(dark: PaletteColor(hex: 0x8A_6B00), light: PaletteColor(hex: 0x7A_5E00)),
        .green: Entry(dark: PaletteColor(hex: 0x2E_7D32), light: PaletteColor(hex: 0x27_682B)),
        .teal: Entry(dark: PaletteColor(hex: 0x00_696E), light: PaletteColor(hex: 0x00_5B60)),
        .blue: Entry(dark: PaletteColor(hex: 0x15_65C0), light: PaletteColor(hex: 0x12_57A6)),
        .indigo: Entry(dark: PaletteColor(hex: 0x3F_3D9E), light: PaletteColor(hex: 0x37_358A)),
        .purple: Entry(dark: PaletteColor(hex: 0x7B_1FA2), light: PaletteColor(hex: 0x6B_1B8D)),
        .pink: Entry(dark: PaletteColor(hex: 0xAD_1457), light: PaletteColor(hex: 0x97_124C)),
        .gray: Entry(dark: PaletteColor(hex: 0x4E_5257), light: PaletteColor(hex: 0x43_474B)),
    ]

    /// Falls back rather than crashing on a missing entry, for the same reason the core
    /// decodes an unknown colour name as the default: a paint colour must never be able to
    /// stop an account from being shown.
    static func entry(for color: AccountColor) -> Entry {
        entries[color] ?? entries[.blue]!
    }

    static func base(for color: AccountColor, in scheme: ColorScheme) -> PaletteColor {
        entry(for: color).base(for: scheme)
    }

    /// The two stops of a card's background, lightest first.
    static func stops(for color: AccountColor, in scheme: ColorScheme) -> [PaletteColor] {
        let base = base(for: color, in: scheme)
        return [base, base.darkened(by: gradientDepth)]
    }

    static func gradient(for color: AccountColor, in scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: stops(for: color, in: scheme).map(\.color),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
