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

        /// The ring once the code is nearly gone.
        ///
        /// Red at Xavier's call, over an earlier amber. The argument for amber was that
        /// the code is still perfectly valid and red says it is not; the argument for red
        /// is that it is the colour people actually read as "hurry", and hesitating for a
        /// second costs nothing while typing a code that expires mid login costs a retry.
        ///
        /// Bright rather than deep, because the palette's own red card is dark and a deep
        /// red ring would disappear into it.
        static let ringExpiring = Color(.sRGB, red: 1, green: 0.35, blue: 0.32)
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
        static let size: CGFloat = 29
        static let lineWidth: CGFloat = 4.5

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

        /// Base point size for the code.
        ///
        /// A number rather than a text style, because the code should be larger than
        /// `.largeTitle` and that is the largest style there is. The card scales it with
        /// `@ScaledMetric`, so it still grows and shrinks with the reader's text size
        /// setting rather than being pinned at one size.
        static let codeSize: CGFloat = 42
    }
}
