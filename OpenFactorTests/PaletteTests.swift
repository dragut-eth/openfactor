import OpenFactorCore
import SwiftUI
import Testing

@testable import OpenFactor

/// The palette's central claim is that white text is legible on every card. That is a
/// number, not an opinion, so it is asserted rather than eyeballed.
///
/// These live in the app's test target because the palette is interface, not core. They
/// run under `xcodebuild test` and not under `swift test`.
@Suite("Palette contrast")
struct PaletteTests {

    /// WCAG 2.1 AA for body text. The account name is the smallest text on a card, so the
    /// whole palette is held to the stricter of the two thresholds rather than to the 3 to
    /// 1 that the large code digits could have got away with.
    static let requiredRatio = 4.5

    static let schemes: [ColorScheme] = [.light, .dark]

    @Test("Every card colour carries white text legibly", arguments: AccountColor.allCases)
    func everyColorMeetsContrast(color: AccountColor) {
        for scheme in Self.schemes {
            for (index, stop) in Palette.stops(for: color, in: scheme).enumerated() {
                let ratio = stop.contrastRatio(against: .white)

                #expect(
                    ratio >= Self.requiredRatio,
                    """
                    \(color.rawValue) in \(scheme == .dark ? "dark" : "light") scheme, \
                    gradient stop \(index), has contrast \(String(format: "%.2f", ratio)) \
                    against white. Minimum is \(Self.requiredRatio). Darken the entry.
                    """
                )
            }
        }
    }

    /// The account name is drawn at partial opacity, so what matters is the colour that
    /// results from compositing it over the card, not the white it started as.
    @Test("Dimmed text on a card is still legible", arguments: AccountColor.allCases)
    func secondaryTextMeetsContrast(color: AccountColor) {
        let opacity = 0.78

        for scheme in Self.schemes {
            for stop in Palette.stops(for: color, in: scheme) {
                let composited = PaletteColor(
                    opacity + (1 - opacity) * stop.red,
                    opacity + (1 - opacity) * stop.green,
                    opacity + (1 - opacity) * stop.blue
                )
                let ratio = composited.contrastRatio(against: stop)

                #expect(
                    ratio >= 3.0,
                    """
                    \(color.rawValue): dimmed text composites to a contrast of \
                    \(String(format: "%.2f", ratio)) against its card. \
                    Raise the opacity in Tokens.OnCard.secondary.
                    """
                )
            }
        }
    }

    /// A gradient that lightened toward the bottom would put the worst case somewhere the
    /// tests above do not look. Darkening keeps the base colour the worst case.
    @Test("The gradient only ever darkens", arguments: AccountColor.allCases)
    func gradientDarkens(color: AccountColor) {
        for scheme in Self.schemes {
            let stops = Palette.stops(for: color, in: scheme)
            #expect(stops.count == 2)
            #expect(stops[1].relativeLuminance < stops[0].relativeLuminance)
        }
    }

    @Test("Every colour name has an entry")
    func paletteIsComplete() {
        for color in AccountColor.allCases {
            #expect(Palette.entries[color] != nil, "No palette entry for \(color.rawValue)")
        }
    }

    /// The two scheme variants should be different, or one of them is unconsidered, and
    /// both should stay dark enough for white text, which the contrast test already covers.
    @Test("The two scheme variants differ", arguments: AccountColor.allCases)
    func schemeVariantsDiffer(color: AccountColor) {
        let entry = Palette.entry(for: color)
        #expect(entry.dark != entry.light)
    }

    // MARK: - The contrast maths itself

    /// The palette is only as trustworthy as the function judging it, so the function is
    /// checked against the two ratios everyone knows.
    @Test("Contrast ratios match the published extremes")
    func contrastMathIsCorrect() {
        let black = PaletteColor(0, 0, 0)
        let white = PaletteColor.white

        #expect(abs(black.contrastRatio(against: white) - 21) < 0.01)
        #expect(abs(white.contrastRatio(against: white) - 1) < 0.01)

        // Mid grey, #767676, is the lightest grey that reaches 4.5 to 1 against white and
        // is the standard worked example for the threshold.
        let midGrey = PaletteColor(hex: 0x76_7676)
        #expect(midGrey.contrastRatio(against: white) >= 4.5)
        #expect(midGrey.contrastRatio(against: white) < 4.6)
    }

    @Test("Hex parsing produces the right components")
    func hexParsing() {
        let color = PaletteColor(hex: 0x00_80FF)

        #expect(abs(color.red - 0) < 0.001)
        #expect(abs(color.green - 128.0 / 255) < 0.001)
        #expect(abs(color.blue - 1) < 0.001)
    }
}

@Suite("Code formatting")
struct CodeFormattingTests {

    private static let thinSpace = "\u{2009}"

    @Test("Six digit codes split into threes")
    func groupsSixDigits() {
        #expect(CodeFormatting.grouped("751702") == "751\(Self.thinSpace)702")
    }

    @Test("Eight digit codes split into fours")
    func groupsEightDigits() {
        #expect(CodeFormatting.grouped("94287082") == "9428\(Self.thinSpace)7082")
    }

    /// Seven does not divide evenly, and a lopsided split is worse than none.
    @Test("Seven digit codes are left alone")
    func leavesSevenDigitsAlone() {
        #expect(CodeFormatting.grouped("9428708") == "9428708")
    }

    /// Grouping is decoration. Removing it must give back exactly what the generator
    /// produced, or the wrong thing is on screen.
    @Test("Grouping never changes the digits", arguments: ["000000", "751702", "94287082", "07081804"])
    func groupingPreservesDigits(code: String) {
        let grouped = CodeFormatting.grouped(code)
        #expect(grouped.filter(\.isNumber) == code)
    }

    /// Without this VoiceOver reads 751702 as "seven hundred fifty one thousand, seven
    /// hundred two", which nobody can type into a login form.
    @Test("Codes are spoken one digit at a time")
    func spellsOutDigits() {
        #expect(CodeFormatting.spokenDigits("751702") == "7 5 1 7 0 2")
    }
}

@Suite("Account card model")
struct AccountCardModelTests {

    private func model(remaining: TimeInterval, period: Int = 30) -> AccountCard.Model {
        AccountCard.Model(
            issuer: "GitHub",
            name: "octocat",
            code: "751702",
            secondsRemaining: remaining,
            period: period,
            color: .blue
        )
    }

    @Test(
        "The ring reflects how much of the code's life is left",
        arguments: [
            (remaining: 30.0, fraction: 1.0),
            (remaining: 15.0, fraction: 0.5),
            (remaining: 0.0, fraction: 0.0),
        ]
    )
    func fractionTracksRemaining(remaining: TimeInterval, fraction: Double) throws {
        let actual = try #require(model(remaining: remaining).fractionRemaining)
        #expect(abs(actual - fraction) < 0.001)
    }

    /// A clock that jumps, or a period that changed under the app, must not produce a ring
    /// drawn outside its own circle.
    @Test("The ring cannot be drawn beyond full or below empty", arguments: [-100.0, -1.0, 31.0, 10_000.0])
    func fractionIsClamped(remaining: TimeInterval) throws {
        let fraction = try #require(model(remaining: remaining).fractionRemaining)
        #expect(fraction >= 0 && fraction <= 1)
    }

    /// The core refuses to build a configuration with a period of zero, so this can only
    /// happen through a bug. It still must not divide by it.
    @Test("A period of zero draws no ring rather than dividing by zero")
    func zeroPeriodIsSafe() {
        #expect(model(remaining: 10, period: 0).fractionRemaining == nil)
    }

    /// A counter based account has nothing to count down, so it gets no ring at all
    /// rather than one that never moves.
    @Test("No countdown means no ring")
    func noCountdownMeansNoRing() {
        var subject = model(remaining: 10)
        subject.secondsRemaining = nil

        #expect(subject.fractionRemaining == nil)
        #expect(subject.isExpiring == false)
    }

    @Test(
        "The ring warns only in the last few seconds",
        arguments: [(remaining: 30.0, expiring: false), (6.0, false), (5.0, true), (1.0, true)]
    )
    func warnsNearExpiry(remaining: TimeInterval, expiring: Bool) {
        #expect(model(remaining: remaining).isExpiring == expiring)
    }
}
