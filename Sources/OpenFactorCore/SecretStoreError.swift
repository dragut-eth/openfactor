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

    /// This device holds ciphertext and no vault key.
    ///
    /// **Ordinary rather than broken.** It is the state of a fresh install, a reinstall, a new
    /// phone, or a watch that has not been provisioned yet. The interface owes it a passphrase
    /// prompt, or on a watch an offer to ask the phone, and must never present it as damage.
    case vaultLocked

    /// Asked to advance a counter on an account whose codes come from the clock.
    case notCounterBased

    /// A counter based account has reached `UInt64.max` and cannot advance again.
    ///
    /// Unreachable by any human: at one code per second it takes longer than the age of
    /// the universe. It exists because the alternative to checking is wrapping silently
    /// back to zero, which would replay every code the account has ever produced.
    case counterExhausted

    /// Anything else the Keychain reported, carrying the raw status so a bug report can
    /// name it exactly.
    case keychain(status: Int32)

    /// Some accounts could not be moved into the shared access group.
    ///
    /// Its own case rather than a generic failure, because the consequence is specific:
    /// what is left behind stays invisible on the phone, which reads every group it can
    /// reach, and surfaces only as a watch with fewer accounts than it should have.
    /// Gate A2, F20.
    case migrationIncomplete(moved: Int, failed: Int)
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
        case .vaultLocked:
            return """
                This device does not have the key to your accounts yet. Enter your passphrase, \
                or open OpenFactor on your iPhone with this watch nearby.
                """
        case let .unreadableMetadata(id):
            return "The details for account \(id) could not be read. Its secret is intact."
        case .notCounterBased:
            return "This account's codes change on a timer, so there is no next code to ask for."
        case .counterExhausted:
            return "This account has run out of codes and needs to be set up again."
        case let .migrationIncomplete(moved, failed):
            return "Moved \(moved) accounts, and \(failed) could not be moved."

        case let .keychain(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "no description"
            return "The Keychain returned error \(status): \(message)."
        }
    }
}
