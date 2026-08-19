import Foundation
import Testing

@testable import OpenFactorCore

@Suite("otpauth URI serialization")
struct OTPAuthURIRoundTripTests {

    private static func account(
        issuer: String? = "Example",
        name: String = "alice@google.com",
        generator: OTPGenerator = .totp(.standard)
    ) throws -> OTPAccount {
        OTPAccount(
            issuer: issuer,
            name: name,
            secret: try Base32.decode(exampleSecret),
            generator: generator
        )
    }

    /// Pins the exact output. The format is what other authenticators read, so a change
    /// to it is a compatibility change and should be a deliberate edit to this string.
    @Test("The canonical output form")
    func writesCanonicalForm() throws {
        let uri = OTPAuthURI.uri(for: try Self.account())

        #expect(
            uri == "otpauth://totp/Example:alice%40google.com"
                + "?secret=\(exampleSecret)&issuer=Example&algorithm=SHA1&digits=6&period=30"
        )
    }

    /// Round tripping is the property that matters. Everything below is one account,
    /// written out, read back, and compared.
    @Test(
        "Accounts survive being written and read back",
        arguments: [
            "alice@google.com",
            "alice",
            "",
            "Ada Lovelace",
            "user+tag@example.com",
            "café@example.com",
            "user name with spaces",
            "100% real",
            "a/b/c",
            "?query=like",
            "#fragment",
            "&ampersand",
            "emoji 🔐 name",
        ]
    )
    func roundTripsNames(name: String) throws {
        let original = try Self.account(name: name)
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed == original)
    }

    @Test(
        "Issuers survive being written and read back",
        arguments: [
            "Example",
            "Amazon Web Services",
            "Company: The Sequel",
            "Ünïcøde Ltd",
            "a&b",
        ]
    )
    func roundTripsIssuers(issuer: String) throws {
        let original = try Self.account(issuer: issuer)
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed == original)
    }

    @Test("Accounts with no issuer survive")
    func roundTripsWithoutIssuer() throws {
        let original = try Self.account(issuer: nil)
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed == original)
        #expect(parsed.issuer == nil)
    }

    /// With no issuer, a colon in the name reads exactly like the separator. The writer
    /// emits an empty issuer prefix so the first colon is unambiguously the separator.
    /// Without that, `server:8080` would come back as issuer `server`, name `8080`.
    @Test("A colon in the name survives when there is no issuer", arguments: ["server:8080", "a:b:c", ":leading"])
    func roundTripsColonInNameWithoutIssuer(name: String) throws {
        let original = try Self.account(issuer: nil, name: name)
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed == original)
        #expect(parsed.issuer == nil)
        #expect(parsed.name == name)
    }

    @Test(
        "Every generator configuration survives",
        arguments: [
            OTPGenerator.totp(.standard),
            .hotp(counter: 0, digits: .six, algorithm: .sha1),
            // The ceiling rather than UInt64.max: a counter beyond what the backup format can
            // represent is refused at enrollment now, and `hugeCounterIsRefused` pins that.
            .hotp(counter: AccountLimits.maximumCounter, digits: .eight, algorithm: .sha512),
        ]
    )
    func roundTripsGenerators(generator: OTPGenerator) throws {
        let original = try Self.account(generator: generator)
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed == original)
    }

    @Test("Every time based combination survives")
    func roundTripsEveryTimeBasedCombination() throws {
        for algorithm in OTPAlgorithm.allCases {
            for digits in OTPDigits.allCases {
                for period in [1, 15, 30, 60, 3600] {
                    let configuration = try TOTPConfiguration(
                        algorithm: algorithm,
                        digits: digits,
                        period: period
                    )
                    let original = try Self.account(generator: .totp(configuration))
                    let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

                    #expect(parsed == original)
                }
            }
        }
    }

    /// Secrets of every storable length, since the padding decision in the writer is the kind
    /// of thing that works for one length and not the next.
    ///
    /// **The range starts at the floor rather than at one, and that is a behaviour change
    /// rather than a weakened test.** Gate A4 found that a secret shorter than RFC 4226's
    /// minimum enrolled here, worked every day, and was refused by the backup format on
    /// restore. The parser rejects those now, and `shortSecretsAreRefused` below pins the other
    /// half so this range cannot quietly be narrowed again to make something pass.
    @Test(
        "Secrets of any storable length survive",
        arguments: AccountLimits.minimumSecretBytes...40)
    func roundTripsSecrets(length: Int) throws {
        let secret = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 53 &+ 7) })
        let original = OTPAccount(issuer: "X", name: "y", secret: secret, generator: .totp(.standard))
        let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

        #expect(parsed.secret == secret)
    }

    /// The half that makes the range above honest: everything below the floor is refused, and
    /// refused for the right reason.
    @Test("A secret below the floor is refused", arguments: 1..<AccountLimits.minimumSecretBytes)
    func shortSecretsAreRefused(length: Int) throws {
        let secret = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 53 &+ 7) })
        let original = OTPAccount(issuer: "X", name: "y", secret: secret, generator: .totp(.standard))
        let uri = OTPAuthURI.uri(for: original)

        #expect(throws: OTPAuthURIError.secretTooShort) {
            _ = try OTPAuthURI.account(from: uri)
        }
    }

    /// A counter beyond what the backup format can represent is refused at enrollment, for the
    /// same reason: an account that cannot be restored should not be created.
    @Test("A counter beyond the format's ceiling is refused")
    func hugeCounterIsRefused() {
        let uri = "otpauth://hotp/x?secret=GEZDGNBVGY3TQOJQ&counter=9007199254740992"
        #expect(throws: OTPAuthURIError.invalidCounter("9007199254740992")) {
            _ = try OTPAuthURI.account(from: uri)
        }
    }

    /// A single byte encodes to `AE` plus six padding characters. Padding in a query
    /// value is legal and awkward to read, so the writer leaves it off.
    @Test("The written secret carries no padding")
    func writesUnpaddedSecret() throws {
        let account = OTPAccount(
            issuer: nil,
            name: "a",
            secret: Data([0x01]),
            generator: .totp(.standard)
        )

        let uri = OTPAuthURI.uri(for: account)
        let secretParameter = uri
            .split(separator: "?")[1]
            .split(separator: "&")
            .first { $0.hasPrefix("secret=") }

        #expect(secretParameter == "secret=AE")
    }

    /// The parameters that decide what a code looks like are always written, even when
    /// they match the defaults, so the account generates the same codes wherever it is
    /// imported rather than depending on the reader agreeing about defaults.
    @Test("Defaults are written out rather than left implied")
    func writesDefaultsExplicitly() throws {
        let uri = OTPAuthURI.uri(for: try Self.account())

        #expect(uri.contains("algorithm=SHA1"))
        #expect(uri.contains("digits=6"))
        #expect(uri.contains("period=30"))
    }
}
