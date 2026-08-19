import Foundation

/// Why an archive could not be opened.
///
/// Every case names something a person can act on, because this type is only ever read on
/// the recovery path, by somebody who has already lost the device the accounts were on.
public enum BackupError: Sendable, Equatable, Error {

    /// Not JSON, or not a JSON object at the top level.
    case notAnArchive

    /// A `format` this reader does not implement. Refused rather than attempted: a version 2
    /// archive opened by a version 1 reader would be guesswork on secret material.
    case unsupportedFormat(String)

    case unsupportedKeyDerivation(String)
    case unsupportedCipher(String)

    /// A required field is absent, null, or of the wrong JSON type. `passphrase` is the only
    /// field exempt from this, and it is exempt by design.
    case malformedField(String)

    /// A salt, nonce or tag of the wrong length. Checked rather than assumed, because a
    /// reader that ignores a field it consumes works by accident.
    case wrongLength(field: String, expected: Int, found: Int)

    /// Outside 100,000 to 10,000,000. The ceiling is the one that matters: an `iterations`
    /// of two billion makes a phone grind for an hour before printing the same refusal, and
    /// the reader derives up to four keys, so the worst case is four times whatever this is.
    case iterationsOutOfRange(Int)

    /// Beyond the size the format allows, checked before decoding rather than after.
    case tooLarge

    /// The tag did not verify under any passphrase form, or it verified and the plaintext
    /// was not a payload. The reader cannot tell a wrong passphrase from an altered file,
    /// and must not pretend it can.
    case couldNotOpen

    /// An account in the store cannot be represented in this format, so the export refuses
    /// rather than writing an archive its own reader would turn away.
    ///
    /// **Only reachable for an account enrolled before the enrollment paths enforced these
    /// rules.** Gate A4 found three of four paths admitting secrets and counters the format
    /// forbids, so an account could work every day and be refused by the backup meant to save
    /// it, discovered on a device that no longer had the originals.
    case cannotStoreAccount(label: String)

    /// The system key derivation failed, which for these inputs is a defect here rather than
    /// anything about the file.
    case derivationFailed

    /// A custom passphrase an offline guessing attack finishes too quickly. Refused by the
    /// writer, because version 1 is forever and so is an archive sealed with one.
    case passphraseTooWeak

    /// Written for the person trying to recover their accounts.
    public var description: String {
        switch self {
        case .notAnArchive:
            "This file is not an OpenFactor archive."
        case let .unsupportedFormat(found):
            """
            This archive was written in a format this version of OpenFactor does not \
            understand (\(found)). A newer version may be able to open it.
            """
        case let .unsupportedKeyDerivation(found):
            "This archive uses an unsupported key derivation (\(found))."
        case let .unsupportedCipher(found):
            "This archive uses an unsupported cipher (\(found))."
        case let .malformedField(name):
            "This archive is damaged. Its \(name) is missing or is not the right kind of value."
        case let .wrongLength(field, expected, found):
            "This archive is damaged. Its \(field) is \(found) bytes and should be \(expected)."
        case .iterationsOutOfRange:
            "This archive asks for an amount of work outside what OpenFactor will attempt."
        case .tooLarge:
            "This file is too large to be an OpenFactor archive."
        case .couldNotOpen:
            """
            OpenFactor could not open this archive. Either the passphrase is wrong, or the \
            file has been altered since it was written. There is no way to tell which.
            """
        case let .cannotStoreAccount(label):
            """
            \(label) cannot be written to a backup: its secret is too short, or its counter is \
            too large, for the backup format. It was saved before OpenFactor checked for this. \
            Remove it, or add it again from the service, and export once more.
            """
        case .derivationFailed:
            "OpenFactor could not derive a key on this device."
        case .passphraseTooWeak:
            """
            That passphrase is too easy to guess to protect every account you have. \
            OpenFactor did not write an archive.
            """
        }
    }
}
