import Foundation
import Testing

@testable import OpenFactorCore

/// Everything a scanner might be pointed at that is not a usable account.
///
/// Split out from the parsing suite because refusal is where a parser earns its keep. A
/// permissive parser turns a malformed setup code into an account that generates wrong
/// codes forever, and the user finds out at a login rather than at the scan.
@Suite("otpauth URI rejection")
struct OTPAuthURIRejectionTests {

    @Test(
        "Input that is not a setup code is refused",
        arguments: [
            "",
            "   ",
            "hello",
            "https://example.com/totp/A?secret=\(exampleSecret)",
            "otpauth:",
            "otpauth://",
            "://totp/A",
        ]
    )
    func refusesNonURIs(text: String) {
        #expect(throws: OTPAuthURIError.notAnOTPAuthURI) {
            try OTPAuthURI.account(from: text)
        }
    }

    @Test("An unknown type is refused")
    func refusesUnknownType() {
        #expect(throws: OTPAuthURIError.unsupportedType("steam")) {
            try OTPAuthURI.account(from: "otpauth://steam/A?secret=\(exampleSecret)")
        }
    }

    @Test("A missing secret is refused", arguments: ["otpauth://totp/A", "otpauth://totp/A?secret=", "otpauth://totp/A?issuer=X"])
    func refusesMissingSecret(uri: String) {
        #expect(throws: OTPAuthURIError.missingSecret) {
            try OTPAuthURI.account(from: uri)
        }
    }

    @Test("A malformed secret is refused, with the reason kept")
    func refusesMalformedSecret() {
        #expect(throws: OTPAuthURIError.malformedSecret(.invalidCharacter("1", offset: 0))) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=1111")
        }
    }

    /// Eight padding characters are valid Base32 and decode to nothing. HMAC would accept
    /// the empty key and generate codes that are wrong everywhere.
    @Test("A secret that decodes to nothing is refused")
    func refusesEmptySecret() {
        #expect(throws: OTPAuthURIError.emptySecret) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=========")
        }
    }

    @Test("An unsupported algorithm is refused")
    func refusesUnsupportedAlgorithm() {
        #expect(throws: OTPAuthURIError.unsupportedAlgorithm("MD5")) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=\(exampleSecret)&algorithm=MD5")
        }
    }

    @Test("An unsupported digit count is refused", arguments: ["9", "5", "0", "six", "6.0"])
    func refusesUnsupportedDigits(digits: String) {
        #expect(throws: OTPAuthURIError.unsupportedDigits(digits)) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=\(exampleSecret)&digits=\(digits)")
        }
    }

    @Test("A period that is not a number is refused")
    func refusesNonNumericPeriod() {
        #expect(throws: OTPAuthURIError.invalidPeriod("thirty")) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=\(exampleSecret)&period=thirty")
        }
    }

    /// The range is TOTPConfiguration's rule, and the parser surfaces its error rather
    /// than restating the bounds. One rule, one place.
    @Test("A period out of range is refused by the type that owns the range", arguments: [0, -30, 86_400])
    func refusesOutOfRangePeriod(period: Int) {
        #expect(throws: OTPAuthURIError.invalidConfiguration(.invalidPeriod(period))) {
            try OTPAuthURI.account(from: "otpauth://totp/A?secret=\(exampleSecret)&period=\(period)")
        }
    }

    /// Defaulting a missing counter to zero would produce an account whose codes are
    /// rejected forever, and would hide the problem at the one moment it is still fixable.
    @Test("A counter based account with no counter is refused")
    func refusesMissingCounter() {
        #expect(throws: OTPAuthURIError.missingCounter) {
            try OTPAuthURI.account(from: "otpauth://hotp/A?secret=\(exampleSecret)")
        }
    }

    @Test("An invalid counter is refused", arguments: ["-1", "one", "1.5", "99999999999999999999999"])
    func refusesInvalidCounter(counter: String) {
        #expect(throws: OTPAuthURIError.invalidCounter(counter)) {
            try OTPAuthURI.account(from: "otpauth://hotp/A?secret=\(exampleSecret)&counter=\(counter)")
        }
    }

    // MARK: - Robustness

    /// Every prefix of a valid URI must either parse or throw. A scanner points at
    /// whatever is in front of it and this is the cheapest approximation of that: a
    /// hundred odd truncations, none of which may crash, hang, or return an account that
    /// is only half filled in.
    @Test("No prefix of a valid URI can crash the parser")
    func survivesEveryPrefix() {
        let valid = "otpauth://totp/Example:alice@google.com?secret=\(exampleSecret)&issuer=Example&digits=8"

        for length in 0...valid.count {
            let prefix = String(valid.prefix(length))

            if let account = try? OTPAuthURI.account(from: prefix) {
                // Anything that parses is complete, never partial.
                #expect(!account.secret.isEmpty)
            }
        }
    }

    @Test(
        "Deliberately awkward input is refused rather than mishandled",
        arguments: [
            "otpauth://totp/%%%?secret=\(exampleSecret)&digits=%%",
            "otpauth://totp/A?secret=\(exampleSecret)&period=999999999999999999999",
            "otpauth://totp/A?secret=\(exampleSecret)&&&",
            "otpauth://totp/" + String(repeating: "A", count: 5_000) + "?secret=\(exampleSecret)&digits=9",
            "otpauth://hotp/A?secret=\(exampleSecret)&counter=",
            "otpauth://totp/:::::?secret=\(exampleSecret)&digits=7&digits=9",
        ]
    )
    func handlesAwkwardInput(text: String) {
        // The contract is only that it returns or throws, never that it succeeds.
        _ = try? OTPAuthURI.account(from: text)
    }
}
