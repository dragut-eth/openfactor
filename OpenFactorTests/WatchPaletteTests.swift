import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

/// The watch palette has the opposite job to the phone's, so it needs its own numbers.
///
/// On the phone a card colour sits behind white text, so every entry has to be dark. On the
/// watch the colour *is* the text and the ground is black, so every entry has to be light.
/// Reusing the phone's values would have put a dark colour on black, the one pairing they
/// were never checked for, and it would have looked fine to whoever picked them and been
/// unreadable in sunlight.
///
/// The tinted row makes it a three way constraint, which is why it is asserted rather than
/// eyeballed: the issuer must clear its own tinted background, and the tint must stay dark
/// enough for white text too, since the account name sits on the same row.
@Suite("Watch palette contrast")
struct WatchPaletteTests {

    /// WCAG 2.1 AA for body text. The watch is read at arm's length, outdoors, in a glance,
    /// so it gets the stricter threshold rather than the 3 to 1 large text could claim.
    static let requiredRatio = 4.5

    @Test("Every issuer colour is legible on black", arguments: AccountColor.allCases)
    func legibleOnBlack(color: AccountColor) {
        let ratio = WatchPalette.entry(for: color).contrastRatio(against: .black)

        #expect(
            ratio >= Self.requiredRatio,
            """
            \(color.rawValue) has contrast \(String(format: "%.2f", ratio)) against black. \
            Minimum is \(Self.requiredRatio). Lighten the entry.
            """
        )
    }

    @Test("Every issuer colour survives its own tinted row", arguments: AccountColor.allCases)
    func legibleOnItsOwnRow(color: AccountColor) {
        let ratio = WatchPalette.entry(for: color)
            .contrastRatio(against: WatchPalette.rowBackground(for: color))

        #expect(
            ratio >= Self.requiredRatio,
            """
            \(color.rawValue) has contrast \(String(format: "%.2f", ratio)) against its own \
            tinted row. Minimum is \(Self.requiredRatio). Reduce WatchPalette.rowTint or \
            lighten the entry.
            """
        )
    }

    /// The account name is white and sits on the same tinted row as the coloured issuer, so
    /// the tint is squeezed from both sides: light enough to be visible, dark enough to
    /// carry white.
    @Test("Every tinted row still carries white text", arguments: AccountColor.allCases)
    func rowCarriesWhiteText(color: AccountColor) {
        let ratio = WatchPalette.rowBackground(for: color).contrastRatio(against: .white)

        #expect(
            ratio >= Self.requiredRatio,
            """
            The \(color.rawValue) row has contrast \(String(format: "%.2f", ratio)) against \
            white. Minimum is \(Self.requiredRatio). Reduce WatchPalette.rowTint.
            """
        )
    }

    /// A tint nobody can see is not worth the code that draws it.
    @Test("The tint is actually visible against black", arguments: AccountColor.allCases)
    func tintIsVisible(color: AccountColor) {
        let ratio = WatchPalette.rowBackground(for: color).contrastRatio(against: .black)

        #expect(
            ratio > 1.1,
            """
            The \(color.rawValue) row is indistinguishable from black at \
            \(String(format: "%.3f", ratio)). Raise WatchPalette.rowTint.
            """
        )
    }
}
