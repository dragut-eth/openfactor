import Foundation

/// Reading a Google Authenticator export QR code.
///
/// The code encodes `otpauth-migration://offline?data=` followed by base64 of a protobuf
/// `MigrationPayload`. The schema is not published by Google; it is
/// [Alex Bakker's reconstruction](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html),
/// which every other authenticator that reads these also works from.
///
/// ```proto
/// message MigrationPayload {
///   repeated OtpParameters otp_parameters = 1;
///   int32 version    = 2;
///   int32 batch_size = 3;
///   int32 batch_index = 4;
///   int32 batch_id   = 5;
///
///   message OtpParameters {
///     bytes  secret    = 1;
///     string name      = 2;
///     string issuer    = 3;
///     Algorithm algorithm = 4;   // 1 SHA1, 2 SHA256, 3 SHA512, 4 MD5
///     DigitCount digits   = 5;   // 1 six, 2 eight
///     OtpType type        = 6;   // 1 hotp, 2 totp
///     int64  counter      = 7;
///   }
/// }
/// ```
///
/// **The secret is raw bytes here, not Base32.** Every other format this app reads carries
/// the secret as text, so the instinct is to decode it, and doing so would produce an
/// account that generates plausible codes no service accepts. The bytes go straight through.
///
/// **There is no period field, and 30 is not a guess.** Google Authenticator has no
/// interface for changing it and every code it produces uses it, so absence here means the
/// value rather than a missing one. That is the same rule Aegis gets and the labelled text
/// reader is denied: a published or reconstructed schema with a fixed value may default; a
/// human readable report that normally writes every field may not.
public enum GoogleAuthenticatorImport {

    public static let scheme = "otpauth-migration"

    /// Why a whole code could not be read, as opposed to one account inside it.
    public enum FileError: Sendable, Equatable, Error {
        case notAMigrationCode
        case malformed

        public var description: String {
            switch self {
            case .notAMigrationCode:
                "This is not a Google Authenticator export code."
            case .malformed:
                """
                This looks like a Google Authenticator export, but OpenFactor could not read \
                it. In Google Authenticator, transfer the accounts again to make a fresh code.
                """
            }
        }
    }

    /// The largest value accepted for a batch's index or size.
    ///
    /// Deliberately small. A transfer split into more parts than this is not a transfer anybody
    /// is going to scan, so a larger number is a malformed message rather than an ambitious
    /// export, and refusing it here keeps every arithmetic on these fields trivially safe.
    ///
    /// **Not the identifier.** This bound used to apply to `batch_id` as well, on the reasoning
    /// above, which is about how many codes a person could scan and says nothing about a number
    /// that only tells parts of one transfer apart. Google writes that field as an `int32` and a
    /// valid transfer carrying a large one was refused whole as malformed. Audit X3, OF-X3-04.
    /// The identifier gets the wire type's range, `maximumBatchIdentifier`, and nothing here
    /// does arithmetic on it.
    static let maximumBatchField = 10_000

    /// The largest `batch_id` accepted: the `int32` the schema declares it as.
    static let maximumBatchIdentifier = UInt64(Int32.max)

    /// One scanned code: the accounts it held, and where it sits in a set.
    ///
    /// A large export does not fit in one QR code, so Google Authenticator splits it. Each
    /// part carries its position, its total, and an identifier shared by the parts of one
    /// export. All three are surfaced rather than folded away, because a person who scans one
    /// part of three and is told "12 accounts found" has been told something true and
    /// misleading at once.
    public struct Batch: Sendable, Equatable {
        public let result: ImportResult
        public let index: Int
        public let size: Int
        public let id: Int

        /// True when this code is the whole export rather than part of one.
        public var isComplete: Bool { size <= 1 }

        /// Which part this is, counting from one, the way it would be said aloud.
        ///
        /// The addition is safe because `index` is refused above `maximumBatchField` when the
        /// message is read, so it cannot approach the top of `Int`.
        ///
        /// **`&+` is a wrapping add, not a saturating one**, and the comment here used to call it
        /// saturating. Swift has no saturating operator; `Int.max &+ 1` is `Int.min`. So the
        /// belt this described does not exist: if the invariant above ever moved, this would show
        /// a hugely negative part number rather than stopping at a ceiling. Two reviewers found
        /// the word in round two. It is kept as `&+` rather than `+` deliberately: the invariant
        /// is proven and tested, and a trap while a sheet is being built is the worst place in
        /// the app to discover otherwise.
        public var position: Int { index &+ 1 }
    }

    /// Whether a scanned string is one of these at all.
    ///
    /// Asked before anything else so that the interface can say what the code *is* rather
    /// than that it is not a setup code, which was true and useless at exactly the moment
    /// somebody was trying to move in.
    public static func looksLikeMigration(_ text: String) -> Bool {
        text.lowercased().hasPrefix("\(scheme)://")
    }

    public static func read(_ text: String) throws(FileError) -> Batch {
        guard looksLikeMigration(text) else { throw .notAMigrationCode }

        guard
            let components = URLComponents(string: text),
            let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value,
            let payload = BackupBase64.decode(encoded)
        else {
            throw .malformed
        }

        let fields: [ProtobufReader.Field]
        do {
            fields = try ProtobufReader.fields(in: payload)
        } catch {
            throw .malformed
        }

        var accounts: [ImportedAccount] = []
        var refusals: [ImportRefusal] = []
        var index = 0
        var size = 1
        var id = 0
        var position = 0

        for field in fields {
            switch field {
            case let .lengthDelimited(1, bytes):
                position += 1
                switch parameters(bytes, sortIndex: accounts.count) {
                case let .success(imported):
                    accounts.append(imported)
                case let .failure(refusal):
                    refusals.append(
                        ImportRefusal(
                            position: position, label: refusal.label, reason: refusal.reason
                        )
                    )
                }

            // **Refused rather than clamped, and the difference crashed the app.** These were
            // `Int(clamping:)`, which turns a nonsensical `UInt64.max` into a perfectly valid
            // `Int.max`, and `Batch.position` then computed `index + 1` and trapped. Gate A4
            // reproduced it from a URL any app on the device can send, since
            // `otpauth-migration://` is a declared scheme, so this was a crash with no user
            // action beyond the link being opened.
            //
            // Clamping is the wrong instinct for a value somebody else chose. It converts
            // "this cannot be true" into "this is the largest thing that can be true", which is
            // still a lie and now an unrefusable one. A batch cannot have more parts than a
            // person could ever scan, so anything outside a sane range is a malformed message.
            case let .varint(3, value):
                guard value <= UInt64(Self.maximumBatchField) else { throw .malformed }
                size = Int(value)
            case let .varint(4, value):
                guard value <= UInt64(Self.maximumBatchField) else { throw .malformed }
                index = Int(value)
            case let .varint(5, value):
                guard value <= Self.maximumBatchIdentifier else { throw .malformed }
                id = Int(value)

            // Everything else, including `version`, is ignored the way an unknown field is.
            default: continue
            }
        }

        // A code with no accounts and no refusals is not an export, whatever it decoded to.
        // Reporting "nothing found" for a QR code that happened to base64 decode would be a
        // worse answer than saying it could not be read.
        guard position > 0 else { throw .malformed }

        return Batch(
            result: ImportResult(accounts: accounts, refusals: refusals),
            index: index,
            size: max(size, 1),
            id: id
        )
    }

    // MARK: - One account

    /// A refusal carrying the best label the record had before it failed, so the preview can
    /// name which account did not come across rather than only its position.
    private struct Failure: Error {
        let label: String?
        let reason: ImportRefusal.Reason
    }

    private static func parameters(
        _ data: Data,
        sortIndex: Int
    ) -> Result<ImportedAccount, Failure> {
        let fields: [ProtobufReader.Field]
        do {
            fields = try ProtobufReader.fields(in: data)
        } catch {
            return .failure(Failure(label: nil, reason: .malformed))
        }

        var secret: Data?
        var name = ""
        var issuer: String?
        var algorithmValue: UInt64 = 0
        var digitsValue: UInt64 = 0
        var typeValue: UInt64 = 0
        var counter: UInt64 = 0

        for field in fields {
            switch field {
            case let .lengthDelimited(1, bytes): secret = Data(bytes)
            case let .lengthDelimited(2, bytes): name = String(decoding: bytes, as: UTF8.self)
            case let .lengthDelimited(3, bytes):
                let text = String(decoding: bytes, as: UTF8.self)
                issuer = text.isEmpty ? nil : text
            case let .varint(4, value): algorithmValue = value
            case let .varint(5, value): digitsValue = value
            case let .varint(6, value): typeValue = value
            case let .varint(7, value): counter = value
            default: continue
            }
        }

        let label = issuer ?? (name.isEmpty ? nil : name)

        guard let secret, !secret.isEmpty else {
            return .failure(Failure(label: label, reason: .missingSecret))
        }
        // RFC 4226's minimum, read from `AccountLimits` rather than spelled out again, because
        // that type exists so the rule has one home and this was the reader still holding its own
        // copy. Round two of gate A4 found it in the commit titled "the class sweep".
        //
        // **And the reason is the true one.** This said `secretNotBase32`, which claims the
        // secret "contains characters that are not valid", in a format whose secrets are raw
        // bytes and have no characters at all. Four readers were corrected and this one was
        // missed, so somebody debugging a refused migration hunted for a bad character in a field
        // that cannot have one.
        guard AccountLimits.isSecretLongEnough(secret) else {
            return .failure(Failure(label: label, reason: .secretTooShort))
        }

        // Their enumerations are not ours, and the gaps are refused by name rather than
        // guessed. MD5 is a value they permit and this app deliberately does not implement,
        // and seven digit codes have no value here at all.
        let algorithm: OTPAlgorithm
        switch algorithmValue {
        case 1: algorithm = .sha1
        case 2: algorithm = .sha256
        case 3: algorithm = .sha512
        case 4:
            return .failure(Failure(label: label, reason: .unsupportedAlgorithm("MD5")))
        default:
            return .failure(Failure(label: label, reason: .missingSetting(.algorithm)))
        }

        let digits: OTPDigits
        switch digitsValue {
        case 1: digits = .six
        case 2: digits = .eight
        default:
            return .failure(Failure(label: label, reason: .missingSetting(.digits)))
        }

        let generator: OTPGenerator
        switch typeValue {
        case 1:
            guard counter <= BackupPayload.maximumCounter else {
                return .failure(Failure(label: label, reason: .malformed))
            }
            generator = .hotp(counter: counter, digits: digits, algorithm: algorithm)
        case 2:
            do {
                generator = .totp(
                    try TOTPConfiguration(algorithm: algorithm, digits: digits, period: 30)
                )
            } catch {
                return .failure(Failure(label: label, reason: .unsupportedPeriod(30)))
            }
        default:
            return .failure(Failure(label: label, reason: .unsupportedType("unknown")))
        }

        return .success(
            ImportedAccount(
                account: OTPAccount(
                    issuer: issuer, name: name, secret: secret, generator: generator
                ),
                // Google Authenticator has no colour concept, so every account gets the
                // default rather than a guess made from its name.
                color: .default,
                sortIndex: sortIndex
            )
        )
    }
}
