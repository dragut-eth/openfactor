import SwiftUI

/// Every measurement and every non palette colour in the app, in one place.
///
/// The rule this exists to enforce: no view hardcodes a colour, a corner radius, or a
/// spacing. A design change should be a diff to this file, and a light mode regression
/// should be impossible to introduce in a view that never names a colour.
enum Tokens {

    /// Surfaces, which adapt to the colour scheme through the asset system rather than
    /// through a branch in a view.
    ///
    /// `Color.primary`, `.secondary`, and the semantic system colours already do the right
    /// thing in both schemes, so they are used rather than reinvented. Reaching for a
    /// custom value here would mean maintaining two of everything for no gain.
    enum Surface {
        /// Behind everything.
        static let background = Color(.systemBackground)

        /// Grouped content that sits on the background.
        static let grouped = Color(.secondarySystemBackground)

        static let separator = Color(.separator)
    }

    /// Text drawn on a card, which is always a coloured surface, so these do not vary by
    /// scheme. The palette guarantees the card is dark enough for them.
    enum OnCard {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.78)

        /// The countdown ring in its normal state.
        static let ring = Color.white.opacity(0.9)

        /// The ring once the code is nearly gone. Amber rather than red, because the code
        /// is still perfectly valid and red would say it is not.
        static let ringExpiring = Color(.sRGB, red: 1, green: 0.84, blue: 0.4)
    }

    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let cardGap: CGFloat = 14
    }

    enum Radius {
        static let card: CGFloat = 20
    }

    enum Ring {
        static let size: CGFloat = 26
        static let lineWidth: CGFloat = 3

        /// How long is left when the ring turns amber. See `UI_SPEC.md`.
        static let warningThreshold: TimeInterval = 5
    }

    /// Type styles.
    ///
    /// All of them are built on Dynamic Type, so the app follows the reader's text size
    /// setting instead of shipping fixed point sizes. The code is the one place a design
    /// would normally hardcode a size, and it does not.
    enum Text {
        static let issuer = Font.headline
        static let name = Font.subheadline

        /// The code itself.
        ///
        /// Monospaced with tabular figures, so digits keep their positions rather than
        /// jittering every time the code changes, and grouped for transcription. `.rounded`
        /// keeps it from looking like a terminal.
        static let code = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    }
}
