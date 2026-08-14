import Foundation

/// How many digits a generated code has.
///
/// RFC 4226 section 5.3 requires at least 6 and treats 7 and 8 as optional. Making this
/// an enumeration rather than an `Int` means a code length that no service issues cannot
/// be constructed at all, so nothing downstream has to check for one.
public enum OTPDigits: Int, Sendable, Equatable, CaseIterable, Codable {
    case six = 6
    case seven = 7
    case eight = 8

    /// What almost every service uses.
    public static let `default` = OTPDigits.six

    /// The modulus that reduces a truncated HMAC to this many digits.
    ///
    /// Ten raised to the digit count, written out rather than computed, because these are
    /// the only three values and a table cannot round the way `pow` can.
    var modulus: UInt32 {
        switch self {
        case .six: 1_000_000
        case .seven: 10_000_000
        case .eight: 100_000_000
        }
    }
}
