import OpenFactorCore
import SwiftUI

/// The card palette, inverted for the watch.
///
/// The phone's palette is built to sit *behind* white text, so every entry is dark enough
/// for white to clear 4.5 to 1 on it. On the watch the relationship flips: the screen is
/// black and the colour is the text. Reusing the phone's values would put a dark colour on
/// black, which is the one combination they were never checked for.
///
/// So these are the vivid variants, chosen to clear 4.5 to 1 *against black* rather than
/// under white. They are close to the icon's colours, which have the same job.
///
/// Only the issuer is coloured. The account name is white and the code is white, because a
/// code is the thing you are trying to read at a glance on a small screen in bad light, and
/// colour is worth less there than contrast.
enum WatchPalette {

    static let entries: [AccountColor: PaletteColor] = [
        .red: PaletteColor(hex: 0xEF_5F55),
        .orange: PaletteColor(hex: 0xF0_8A32),
        .yellow: PaletteColor(hex: 0xD7_B02A),
        .green: PaletteColor(hex: 0x4B_B35A),
        .teal: PaletteColor(hex: 0x2C_C0B3),
        .blue: PaletteColor(hex: 0x5A_A9F0),
        .indigo: PaletteColor(hex: 0x8A_8AF2),
        .purple: PaletteColor(hex: 0xC0_7BE0),
        .pink: PaletteColor(hex: 0xF0_6A9A),
        .gray: PaletteColor(hex: 0xB0_B4BA),
    ]

    /// Falls back rather than failing, for the same reason the core decodes an unknown
    /// colour name as the default: a paint colour must never stop an account being shown.
    static func color(for color: AccountColor) -> Color {
        (entries[color] ?? entries[.gray]!).color
    }
}
