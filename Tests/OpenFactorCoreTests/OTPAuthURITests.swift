import Foundation
import Testing

@testable import OpenFactorCore

/// A dummy secret, `JBSWY3DPEHPK3PXP`, which is the one used in the format documentation
/// and in roughly every example ever written. It protects nothing.
let exampleSecret = "JBSWY3DPEHPK3PXP"

@Suite("otpauth URI parsing")
struct OTPAuthURITests {

    // MARK: - What real services emit

    /// These are the shapes services put in their QR codes, reconstructed rather than
    /// captured, so treat them as representative rather than as evidence. The first is
    /// the example from the format documentation itself and is exact.
    @Test(
        "URIs in the shapes services emit",
        arguments: [
            (
                uri: "otpauth://totp/Example:alice@google.com?secret=\(exampleSecret)&issuer=Example",
                issuer: "Example",
                name: "alice@google.com"
            ),
            (
                uri: "otpauth://totp/GitHub:octocat?secret=\(exampleSecret)&issuer=GitHub",
                issuer: "GitHub",
                name: "octocat"
            ),
            (
                uri:
                    "otpauth://totp/Amazon%20Web%20Services:user@example.com?secret=\(exampleSecret)&issuer=Amazon%20Web%20Services",
                issuer: "Amazon Web Services",
                name: "user@example.com"
            ),
            (
                // Percent encoded separator, and the conventional space after it.
                uri: "otpauth://totp/Example%3A%20alice%40google.com?secret=\(exampleSecret)&issuer=Example",
                issuer: "Example",
                name: "alice@google.com"
            ),
            (
                // No issuer anywhere. Legal, and some smaller services do it.
                uri: "otpauth://totp/alice@google.com?secret=\(exampleSecret)",
                issuer: nil,
                name: "alice@google.com"
            ),
            (
                // Issuer in the parameter but not in the label.
                uri: "otpauth://totp/alice@google.com?secret=\(exampleSecret)&issuer=Example",
                issuer: "Example",
                name: "alice@google.com"
            ),
        ]
    )
    func parsesRealWorldURIs(uri: String, issuer: String?, name: String) throws {
        let account = try OTPAuthURI.account(from: uri)

        #expect(account.issuer == issuer)
        #expect(account.name == name)
        #expect(account.secret == (try Base32.decode(exampleSecret)))
        #expect(account.generator == .totp(.standard))
    }

    // MARK: - Defaults

    /// A bare URI means SHA1, 6 digits, 30 seconds. Getting any of these wrong produces
    /// an account that generates plausible codes which the service rejects.
    @Test("Omitted parameters take the documented defaults")
    func appliesDocumentedDefaults() throws {
        let account = try OTPAuthURI.account(from: "otpauth://totp/A?secret=\(exampleSecret)")

        #expect(account.generator == .totp(.standard))
        #expect(account.generator.algorithm == .sha1)
        #expect(account.generator.digits == .six)
    }

    @Test("Every parameter is read when present")
    func readsEveryParameter() throws {
        let uri = """
            otpauth://totp/Example:alice?secret=\(exampleSecret)&issuer=Example\
            &algorithm=SHA512&digits=8&period=60
            """

        let account = try OTPAuthURI.account(from: uri)
        let expected = try TOTPConfiguration(algorithm: .sha512, digits: .eight, period: 60)

        #expect(account.generator == .totp(expected))
    }

    @Test(
        "Algorithm spellings services actually use",
        arguments: [
            ("SHA1", OTPAlgorithm.sha1),
            ("sha1", OTPAlgorithm.sha1),
            ("SHA-1", OTPAlgorithm.sha1),
            ("Sha256", OTPAlgorithm.sha256),
            ("SHA-512", OTPAlgorithm.sha512),
        ]
    )
    func acceptsAlgorithmSpellings(text: String, algorithm: OTPAlgorithm) throws {
        let account = try OTPAuthURI.account(
            from: "otpauth://totp/A?secret=\(exampleSecret)&algorithm=\(text)"
        )
        #expect(account.generator.algorithm == algorithm)
    }

    @Test("The scheme and type are matched without regard to case")
    func ignoresCaseInSchemeAndType() throws {
        let account = try OTPAuthURI.account(from: "OTPAUTH://TOTP/A?secret=\(exampleSecret)")
        #expect(account.generator == .totp(.standard))
    }

    @Test("Parameter names are matched without regard to case")
    func ignoresCaseInParameterNames() throws {
        let account = try OTPAuthURI.account(from: "otpauth://totp/A?SECRET=\(exampleSecret)&Issuer=X")
        #expect(account.issuer == "X")
    }

    /// Services add parameters of their own, none of which change the codes.
    @Test("Unknown parameters are ignored")
    func ignoresUnknownParameters() throws {
        let uri = "otpauth://totp/A?secret=\(exampleSecret)&image=https%3A%2F%2Fx.test%2Fi.png&lock=false"
        #expect(try OTPAuthURI.account(from: uri).generator == .totp(.standard))
    }

    // MARK: - Issuer precedence

    /// When the label prefix and the parameter disagree, the parameter wins. The format
    /// documentation asks for this and other authenticators do it, so an account imported
    /// here is filed under the same name it would be anywhere else.
    @Test("The issuer parameter beats the label prefix")
    func issuerParameterWins() throws {
        let uri = "otpauth://totp/Stale:alice?secret=\(exampleSecret)&issuer=Current"
        let account = try OTPAuthURI.account(from: uri)

        #expect(account.issuer == "Current")
        #expect(account.name == "alice")
    }

    /// A bare colon is the separator wherever one exists, so an encoded colon inside the
    /// issuer stays part of the issuer. Reading the first colon of either kind instead
    /// would silently rename the account, which is the sort of import bug a user only
    /// notices much later.
    @Test("An encoded colon inside the issuer is not the separator")
    func encodedColonInIssuerIsNotTheSeparator() throws {
        let uri = "otpauth://totp/Company%3A%20Ltd:alice?secret=\(exampleSecret)"
        let account = try OTPAuthURI.account(from: uri)

        #expect(account.issuer == "Company: Ltd")
        #expect(account.name == "alice")
    }

    @Test("An empty issuer parameter falls back to the label prefix")
    func emptyIssuerParameterFallsBack() throws {
        let uri = "otpauth://totp/Example:alice?secret=\(exampleSecret)&issuer="
        #expect(try OTPAuthURI.account(from: uri).issuer == "Example")
    }

    // MARK: - Counter based accounts

    @Test("Counter based accounts carry their counter")
    func parsesCounterBasedAccounts() throws {
        let uri = "otpauth://hotp/Example:alice?secret=\(exampleSecret)&counter=42&digits=8"
        let account = try OTPAuthURI.account(from: uri)

        #expect(account.generator == .hotp(counter: 42, digits: .eight, algorithm: .sha1))
    }

    /// A repeated parameter takes its first value. Any rule would do, so it is written
    /// down and tested rather than left to whichever order the dictionary builds in.
    @Test("A repeated parameter takes the first value")
    func repeatedParameterTakesTheFirst() throws {
        let uri = "otpauth://totp/A?secret=\(exampleSecret)&digits=8&digits=6"
        #expect(try OTPAuthURI.account(from: uri).generator.digits == .eight)
    }
}
