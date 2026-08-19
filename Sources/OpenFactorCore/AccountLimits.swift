import Foundation

/// What an account must satisfy to be stored at all, in one place because four places disagreed.
///
/// ## Why this exists
///
/// `docs/BACKUP_FORMAT.md` is normative and frozen: a secret must decode to at least ten bytes,
/// and a counter must be an integer from 0 to 2^53 − 1. The archive reader enforced both, and so
/// would any independent implementation written from the document. **Three of the four enrollment
/// paths enforced neither**, and the archive writer serialized whatever the account held.
///
/// The consequence, reproduced during gate A4 rather than argued: scan
/// `otpauth://totp/x?secret=GEZDGNBV`, which is valid Base32 decoding to five bytes. The account
/// enrolls, generates codes every day, and is written into an encrypted backup. Restoring that
/// backup on a new device refuses it. **The account is gone, and it is discovered at the one
/// moment the originals are no longer available.**
///
/// It needs no attacker: a service issuing a short secret is enough. A hostile QR code does it
/// deliberately, planting an account that quietly drops out of every backup its owner ever takes.
///
/// ## Why the rules live here rather than in the format
///
/// They were in `BackupPayload`, which is the reader, so every other path had to remember to
/// import a rule from a file about archives. One of four did. Rules that describe what an account
/// *is* belong beside the account, and `BackupPayload` now reads them from here so there remains
/// exactly one definition.
///
/// The same reasoning produced `AccountLabel`, and the two are deliberately shaped alike.
public enum AccountLimits {

    /// The fewest bytes a decoded secret may carry.
    ///
    /// RFC 4226's minimum. The reason is not ceremony: HMAC accepts a short or empty key happily
    /// and produces codes that look entirely correct and are rejected by the service forever.
    /// A secret this short is a transcription that lost its tail, not a secret.
    public static let minimumSecretBytes = 10

    /// The largest counter value, which is the largest integer a JSON reader is required to
    /// represent exactly. A counter beyond it cannot survive the backup format.
    public static let maximumCounter: UInt64 = 1 << 53 - 1

    /// Whether a decoded secret is long enough to be one.
    public static func isSecretLongEnough(_ secret: Data) -> Bool {
        secret.count >= minimumSecretBytes
    }

    /// Whether a counter can be stored and restored.
    public static func isCounterStorable(_ counter: UInt64) -> Bool {
        counter <= maximumCounter
    }

    /// Whether an account can be written to a backup and read back.
    ///
    /// **Asked by the writer, not only by the reader.** An account that fails this is one the app
    /// can display and cannot preserve, and the honest moment to say so is while a backup is being
    /// made rather than while one is being restored.
    public static func isStorable(_ account: OTPAccount) -> Bool {
        guard isSecretLongEnough(account.secret) else { return false }

        if case let .hotp(counter, _, _) = account.generator {
            return isCounterStorable(counter)
        }
        return true
    }
}
