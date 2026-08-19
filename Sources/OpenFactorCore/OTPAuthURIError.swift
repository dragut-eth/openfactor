import Foundation

/// Why an `otpauth://` URI was refused.
///
/// Every case exists so the interface can say what is actually wrong. The alternative,
/// one general failure, produces the worst message in any authenticator: a scanned code
/// that "did not work" with no way to find out why.
///
/// Syntax problems are reported here. Values that parse but are out of range are reported
/// by the type that owns the range, wrapped in ``invalidConfiguration(_:)``, so a rule
/// lives in exactly one place.
public enum OTPAuthURIError: Error, Equatable, Sendable {

    /// Not a URI at all, or the scheme was not `otpauth`.
    case notAnOTPAuthURI

    /// The URI names a kind of code this app does not know, so neither `totp` nor `hotp`.
    case unsupportedType(String)

    /// No `secret` parameter. Without it there is nothing to generate from.
    case missingSecret

    /// The secret is not valid Base32. Carries the underlying reason.
    case malformedSecret(Base32Error)

    /// The secret decoded to nothing, so it was empty or pure padding.
    case emptySecret

    /// Valid Base32, decoding to fewer bytes than RFC 4226 requires and than the backup format
    /// will store. See `AccountLimits`.
    case secretTooShort

    /// An `algorithm` this app does not implement.
    case unsupportedAlgorithm(String)

    /// A `digits` value outside the 6 to 8 that RFC 4226 allows.
    case unsupportedDigits(String)

    /// A `period` that is not a whole number.
    case invalidPeriod(String)

    /// A counter based account with no `counter` parameter.
    ///
    /// Not defaulted to zero on purpose. A counter that starts in the wrong place produces
    /// codes that are silently rejected forever, and guessing would hide that from the
    /// user at the one moment they could still fix it.
    case missingCounter

    /// A `counter` that is not a whole number, or is negative.
    case invalidCounter(String)

    /// A value parsed but was out of the range its type permits.
    case invalidConfiguration(TOTPConfigurationError)
}

extension OTPAuthURIError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notAnOTPAuthURI:
            return "This is not an authenticator setup code."
        case let .unsupportedType(type):
            return "This setup code is for \"\(type)\", which OpenFactor does not support."
        case .missingSecret:
            return "This setup code has no secret key in it."
        case let .malformedSecret(reason):
            return "The secret key in this setup code is not valid. \(reason)"
        case .emptySecret:
            return "The secret key in this setup code is empty."
        case .secretTooShort:
            return """
                The secret key in this setup code is too short to work. It was probably cut \
                off. Ask the service to show the code again.
                """
        case let .unsupportedAlgorithm(algorithm):
            let supported = OTPAlgorithm.allCases.map(\.rawValue).joined(separator: ", ")
            return "This account uses \(algorithm), and OpenFactor supports \(supported)."
        case let .unsupportedDigits(digits):
            return "A code cannot be \(digits) digits long. Codes are 6, 7, or 8 digits."
        case let .invalidPeriod(period):
            return "\"\(period)\" is not a valid refresh interval."
        case .missingCounter:
            return "This counter based account does not say which counter value to start from."
        case let .invalidCounter(counter):
            return "\"\(counter)\" is not a valid counter value."
        case let .invalidConfiguration(reason):
            return reason.description
        }
    }
}
