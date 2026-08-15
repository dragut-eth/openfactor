import Foundation

/// What reading someone else's export produced.
///
/// **Nothing is written to the Keychain by an importer.** A reader returns this, the
/// interface shows it, and only then does the user decide. Adding forty accounts is a
/// different act from adding one, and the preview is the difference.
///
/// The refusals matter as much as the accounts. A file of ten where one is unusable must
/// import nine and say which one failed and why: aborting the whole file punishes the user
/// for someone else's bad record, and dropping it silently hands them an authenticator with
/// a hole in it they will find at a login.
public struct ImportResult: Sendable, Equatable {

    /// Accounts that can be added, in the order they appeared.
    public let accounts: [ImportedAccount]

    /// Records that could not be read, each with a reason a person can act on.
    public let refusals: [ImportRefusal]

    public init(accounts: [ImportedAccount], refusals: [ImportRefusal]) {
        self.accounts = accounts
        self.refusals = refusals
    }

    /// True when the file parsed but held nothing at all, which is not an error and is
    /// worth telling the user rather than showing an empty list.
    public var isEmpty: Bool {
        accounts.isEmpty && refusals.isEmpty
    }
}

/// An account read from an export, with the colour its source recorded if there was one.
public struct ImportedAccount: Sendable, Equatable {
    public let account: OTPAccount

    /// The colour the source assigned, when it has a concept of one and it maps onto ours.
    /// Cosmetic, so an unrecognised value becomes the default rather than failing.
    public let color: AccountColor

    public init(account: OTPAccount, color: AccountColor) {
        self.account = account
        self.color = color
    }
}

/// A record that could not be imported, and why.
public struct ImportRefusal: Sendable, Equatable {

    /// Its position in the file, counting from one, so a record with no usable label can
    /// still be pointed at.
    public let position: Int

    /// The best label available, if the record had one before it failed.
    public let label: String?

    public let reason: Reason

    public enum Reason: Sendable, Equatable, Error {
        case secretNotBase32
        case missingSecret
        case unsupportedAlgorithm(String)
        case unsupportedDigits(Int)
        case unsupportedPeriod(Int)
        case unsupportedType(String)

        /// A field that changes the generated code is absent. Never defaulted: a document
        /// that normally writes every field is telling us the parse failed, not that the
        /// default applies.
        case missingSetting(Setting)

        case malformed

        public enum Setting: Sendable, Equatable {
            case algorithm
            case digits
            case period
        }

        /// Written for the person reading the import preview, not for a log.
        public var description: String {
            switch self {
            case .secretNotBase32:
                "the secret key contains characters that are not valid"
            case .missingSecret:
                "there is no secret key"
            case let .unsupportedAlgorithm(name):
                "OpenFactor does not support the \(name) algorithm"
            case let .unsupportedDigits(count):
                "\(count) digit codes are not supported"
            case let .unsupportedPeriod(seconds):
                "a \(seconds) second period is not supported"
            case let .unsupportedType(type):
                "OpenFactor does not support \(type) accounts"
            case let .missingSetting(setting):
                switch setting {
                case .algorithm: "the file does not say which algorithm this code uses"
                case .digits: "the file does not say how many digits this code has"
                case .period: "the file does not say how often this code changes"
                }
            case .malformed:
                "the record is incomplete"
            }
        }
    }

    public init(position: Int, label: String?, reason: Reason) {
        self.position = position
        self.label = label
        self.reason = reason
    }
}
