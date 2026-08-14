import Foundation
import Testing

@testable import OpenFactorCore

/// Metadata is written to the Keychain as JSON, so decoding it is reading input, not
/// restoring state. These tests treat it that way.
@Suite("Account metadata")
struct AccountMetadataTests {

    private func metadata(generator: OTPGenerator = .totp(.standard)) -> AccountMetadata {
        AccountMetadata(
            issuer: "GitHub",
            name: "octocat",
            generator: generator,
            color: .purple,
            sortIndex: 3
        )
    }

    @Test("Metadata survives a round trip through JSON")
    func roundTrips() throws {
        let original = metadata()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccountMetadata.self, from: data)

        #expect(decoded == original)
    }

    @Test("Every generator survives a round trip through JSON")
    func roundTripsEveryGenerator() throws {
        var generators: [OTPGenerator] = [
            .hotp(counter: 0, digits: .six, algorithm: .sha1),
            .hotp(counter: .max, digits: .eight, algorithm: .sha512),
        ]

        for algorithm in OTPAlgorithm.allCases {
            for digits in OTPDigits.allCases {
                for period in [1, 30, 3600] {
                    generators.append(
                        .totp(try TOTPConfiguration(algorithm: algorithm, digits: digits, period: period))
                    )
                }
            }
        }

        for generator in generators {
            let data = try JSONEncoder().encode(metadata(generator: generator))
            let decoded = try JSONDecoder().decode(AccountMetadata.self, from: data)

            #expect(decoded.generator == generator)
        }
    }

    @Test("An account with no issuer survives")
    func roundTripsWithoutIssuer() throws {
        var original = metadata()
        original.issuer = nil

        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(AccountMetadata.self, from: data) == original)
    }

    // MARK: - Decoding is validation

    /// Stored data is input. A record that has been corrupted, edited, or written by
    /// something else must not be able to produce a configuration the type would refuse to
    /// construct. A period of zero is the sharp case: it would divide by zero the first
    /// time a code was generated.
    @Test("A period of zero is refused on decode")
    func refusesZeroPeriodOnDecode() throws {
        let json = Data(
            """
            {"algorithm":"SHA1","digits":6,"period":0}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TOTPConfiguration.self, from: json)
        }
    }

    @Test("An out of range period is refused on decode", arguments: [-1, 0, 86_400])
    func refusesOutOfRangePeriodOnDecode(period: Int) throws {
        let json = Data(
            """
            {"algorithm":"SHA1","digits":6,"period":\(period)}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TOTPConfiguration.self, from: json)
        }
    }

    @Test("An unsupported digit count is refused on decode")
    func refusesBadDigitsOnDecode() throws {
        let json = Data(
            """
            {"algorithm":"SHA1","digits":9,"period":30}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TOTPConfiguration.self, from: json)
        }
    }

    @Test("An unsupported algorithm is refused on decode")
    func refusesBadAlgorithmOnDecode() throws {
        let json = Data(
            """
            {"algorithm":"MD5","digits":6,"period":30}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TOTPConfiguration.self, from: json)
        }
    }

    /// The asymmetry between this and the refusals above is deliberate. An unknown
    /// algorithm changes the codes and must fail. An unknown colour changes a tint, and
    /// failing would let a record written by a newer, bigger palette block the whole list.
    @Test("An unknown colour decodes as the default rather than failing")
    func unknownColorFallsBack() throws {
        let json = Data(
            """
            {"issuer":"GitHub","name":"octocat","color":"chartreuse","sortIndex":0,\
            "generator":{"totp":{"_0":{"algorithm":"SHA1","digits":6,"period":30}}}}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AccountMetadata.self, from: json)
        #expect(decoded.color == .default)
        #expect(decoded.name == "octocat")
    }

    // MARK: - Display

    @Test(
        "The headline falls back sensibly",
        arguments: [
            (issuer: "GitHub", name: "octocat", expected: "GitHub"),
            (issuer: nil, name: "octocat", expected: "octocat"),
            (issuer: "", name: "octocat", expected: "octocat"),
            (issuer: nil, name: "", expected: "Unnamed account"),
        ]
    )
    func displayIssuerFallsBack(issuer: String?, name: String, expected: String) {
        var subject = metadata()
        subject.issuer = issuer
        subject.name = name

        #expect(subject.displayIssuer == expected)
    }
}

@Suite("Account colour")
struct AccountColorTests {

    /// The same issuer has to land on the same colour on every device and after every
    /// reinstall, or the list looks reshuffled for no reason the user can see.
    @Test("A suggested colour is stable for the same issuer")
    func suggestionIsStable() {
        for issuer in ["GitHub", "Google", "AWS", "Okta", "Coinbase"] {
            let first = AccountColor.suggested(forIssuer: issuer)
            #expect(AccountColor.suggested(forIssuer: issuer) == first)
            #expect(AccountColor.suggested(forIssuer: issuer.uppercased()) == first)
        }
    }

    @Test("Suggestions spread across the palette")
    func suggestionsSpread() {
        let issuers = [
            "GitHub", "Google", "AWS", "Okta", "Coinbase", "Microsoft",
            "Dropbox", "Fastmail", "Stripe", "Cloudflare", "Proton", "Bitwarden",
        ]
        let colors = Set(issuers.map { AccountColor.suggested(forIssuer: $0) })

        // Not a demand for perfect distribution, only that it is not collapsing to one.
        #expect(colors.count >= 4)
    }

    @Test("An unnamed account gets the default colour", arguments: [nil, ""])
    func fallsBackToDefault(issuer: String?) {
        #expect(AccountColor.suggested(forIssuer: issuer) == .default)
    }
}
