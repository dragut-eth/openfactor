import Foundation

/// Why a read or write against the store failed.
public enum SecretStoreError: Error, Equatable, Sendable {

    /// No account with that identifier.
    case notFound

    /// An account with that identifier already exists.
    ///
    /// Identifiers are generated when an account is saved, so in practice this means two
    /// devices generated the same one, or a bug reused one. It is not a duplicate of the
    /// account itself: the same service can legitimately be added twice.
    case duplicate

    /// The device is locked, so the secret cannot be decrypted.
    ///
    /// Expected rather than exceptional. Secrets are stored as readable only while the
    /// device is unlocked, so any background work that tries to read one on a locked
    /// device lands here, and should wait rather than treat it as an error.
    case deviceLocked

    /// The stored metadata could not be read back.
    ///
    /// Means the record was written by a newer version, or was corrupted. The account is
    /// still there and its secret is intact, so this is reported rather than repaired: a
    /// store that silently rewrites data it does not understand can destroy an account
    /// that a later version would have read perfectly.
    case unreadableMetadata(id: UUID)

    /// Anything else the Keychain reported, carrying the raw status so a bug report can
    /// name it exactly.
    case keychain(status: Int32)
}

extension SecretStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notFound:
            return "That account is no longer in the Keychain."
        case .duplicate:
            return "An account with that identifier already exists."
        case .deviceLocked:
            return "Unlock the device to read this account."
        case let .unreadableMetadata(id):
            return "The details for account \(id) could not be read. Its secret is intact."
        case let .keychain(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "no description"
            return "The Keychain returned error \(status): \(message)."
        }
    }
}
