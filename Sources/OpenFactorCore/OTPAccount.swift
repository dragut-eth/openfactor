import Foundation

/// Everything needed to generate codes for one account.
///
/// **This type carries a secret, and it is deliberately short lived.** It is the result of
/// parsing an `otpauth://` URI and the input to saving one, nothing more. It is not the
/// stored model: PR 4 splits an account into a secret held in the Keychain and non secret
/// metadata held beside it, precisely so that the list can be drawn without any secret
/// material in memory.
///
/// Because it holds a secret, it deliberately does not conform to `CustomStringConvertible`
/// or `Codable`. Printing or encoding an account should not be one keystroke away.
public struct OTPAccount: Sendable, Equatable {

    /// Who issued the account, for example `GitHub`.
    ///
    /// Optional because a URI can legitimately omit it, though nearly all do include it.
    public let issuer: String?

    /// Which account at that issuer, usually an email address or a username.
    ///
    /// May be empty. A service that issues a URI with no label is unusual but not wrong,
    /// and refusing the import would cost the user an account to protect a cosmetic
    /// concern. The interface asks for a name instead.
    public let name: String

    /// The shared key, already decoded from Base32. Never empty.
    public let secret: Data

    /// How this account's codes are produced.
    public let generator: OTPGenerator

    public init(issuer: String?, name: String, secret: Data, generator: OTPGenerator) {
        // Bounded here as well as in `AccountMetadata`, so the confirmation screen shows
        // the label that will actually be saved. Clamping only at the storage boundary
        // would let a transfer preview promise a name it was about to cut. See
        // `AccountLabel` for why the bound exists and why it truncates rather than refuses.
        self.issuer = AccountLabel.clamped(issuer)
        self.name = AccountLabel.clamped(name)
        self.secret = secret
        self.generator = generator
    }

    /// The code valid at a given moment.
    ///
    /// For a counter based account the moment is ignored, since its codes advance on use
    /// rather than with the clock.
    public func code(at date: Date) -> String {
        switch generator {
        case let .totp(configuration):
            TOTP.code(secret: secret, at: date, configuration: configuration)
        case let .hotp(counter, digits, algorithm):
            HOTP.code(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
        }
    }
}
