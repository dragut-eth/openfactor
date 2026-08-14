import Foundation

/// How an account's codes are produced.
///
/// The two kinds are genuinely different, not a flag on one type. A time based code is a
/// pure function of the clock, while a counter based one advances only when the user asks
/// for the next code, which means the counter is state the app has to store and keep in
/// step with the service. Modelling them as one type with an optional counter would let a
/// time based account carry a meaningless counter, and would let a counter based account
/// exist without one.
public enum OTPGenerator: Sendable, Equatable, Codable {

    /// Time based, RFC 6238. What almost every service issues.
    case totp(TOTPConfiguration)

    /// Counter based, RFC 4226. Rare, and the counter advances on use.
    case hotp(counter: UInt64, digits: OTPDigits, algorithm: OTPAlgorithm)

    /// The `otpauth://` host that names this kind.
    public var uriType: String {
        switch self {
        case .totp: "totp"
        case .hotp: "hotp"
        }
    }

    public var digits: OTPDigits {
        switch self {
        case let .totp(configuration): configuration.digits
        case let .hotp(_, digits, _): digits
        }
    }

    public var algorithm: OTPAlgorithm {
        switch self {
        case let .totp(configuration): configuration.algorithm
        case let .hotp(_, _, algorithm): algorithm
        }
    }
}
