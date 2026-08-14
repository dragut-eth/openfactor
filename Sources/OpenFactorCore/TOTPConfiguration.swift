import Foundation

/// Everything about a time based code except the secret itself.
///
/// The secret is deliberately not part of this type. Configuration is not sensitive and
/// gets stored, copied, and passed around freely, while the secret is read from the
/// Keychain only at the moment a code is generated. Keeping them apart means there is no
/// long lived object holding secret material, and no way to accidentally log one by
/// logging the other.
public struct TOTPConfiguration: Sendable, Equatable {

    /// What the overwhelming majority of services use, and what an `otpauth://` URI means
    /// when it omits the parameters.
    public static let standard = TOTPConfiguration(
        algorithm: .default,
        digits: .default,
        validatedPeriod: 30
    )

    public let algorithm: OTPAlgorithm
    public let digits: OTPDigits

    /// How many seconds each code is valid for. RFC 6238 calls this the time step, X.
    public let period: Int

    /// - Throws: ``TOTPConfigurationError/invalidPeriod(_:)`` if the period is outside
    ///   the supported range. The bounds are not from the RFC, which sets none, but a
    ///   period of zero cannot be divided by and an enormous one produces a code that
    ///   never changes, which is worse than refusing the account outright.
    public init(
        algorithm: OTPAlgorithm = .default,
        digits: OTPDigits = .default,
        period: Int = 30
    ) throws(TOTPConfigurationError) {
        guard Self.supportedPeriods.contains(period) else {
            throw TOTPConfigurationError.invalidPeriod(period)
        }

        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    /// One second to one hour. Real services use 30, occasionally 60.
    ///
    /// Public because the interface needs to know the bounds it is validating against,
    /// and restating them there would give the rule two homes that could disagree.
    public static let supportedPeriods = 1...3600

    /// Skips validation, for constants known to be in range at compile time.
    private init(algorithm: OTPAlgorithm, digits: OTPDigits, validatedPeriod: Int) {
        self.algorithm = algorithm
        self.digits = digits
        self.period = validatedPeriod
    }
}

extension TOTPConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case algorithm
        case digits
        case period
    }

    /// Decoding runs the same validation as the initialiser, deliberately.
    ///
    /// Synthesised decoding would write straight into the stored properties and skip the
    /// range check, which is exactly the wrong behaviour for a value read back from
    /// storage. A period of zero arriving from a corrupted or edited record would divide
    /// by zero the first time a code was generated. Stored data is input like any other.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let algorithm = try container.decode(OTPAlgorithm.self, forKey: .algorithm)
        let digits = try container.decode(OTPDigits.self, forKey: .digits)
        let period = try container.decode(Int.self, forKey: .period)

        do {
            try self.init(algorithm: algorithm, digits: digits, period: period)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .period,
                in: container,
                debugDescription: error.description
            )
        }
    }
}

/// Why a configuration was refused.
public enum TOTPConfigurationError: Error, Equatable, Sendable {
    case invalidPeriod(Int)
}

extension TOTPConfigurationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidPeriod(period):
            let range = TOTPConfiguration.supportedPeriods
            return "A code cannot refresh every \(period) seconds. Use a value from \(range.lowerBound) to \(range.upperBound)."
        }
    }
}
