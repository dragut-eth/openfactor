import CryptoKit
import Foundation

/// What state this device's vault is in, and the three things that can be done about it.
///
/// The whole of the vault's lifecycle is here rather than in a view, because the decisions are
/// about storage and the same ones apply on a watch, where the interface is entirely different.
///
/// ## The three states, and why telling them apart matters
///
/// | Key on this device | Wrapped record present | State |
/// | --- | --- | --- |
/// | yes | either | `open` |
/// | no | no | `absent`, no vault has ever existed |
/// | no | yes | `locked`, this device needs the passphrase it was already given |
///
/// **`absent` and `locked` are different questions and must not be confused.** Absent means
/// create a vault and show a new passphrase. Locked means ask for one that already exists.
/// Getting this backwards asks somebody to type a passphrase that was never issued, or issues a
/// second one and strands everything sealed under the first.
///
/// **Absent is also what a device looks like while the record is still arriving.** iCloud
/// Keychain took close to half an hour to move seven items on this project's own hardware, so a
/// second device set up the same day can read `absent` when it is really `locked`. That is why
/// creation is a deliberate act with a screen and never something this type does on its own.
public struct Vault: Sendable {

    public enum State: Sendable, Equatable {
        case open
        case absent
        case locked
    }

    public enum VaultError: Error, Equatable, Sendable {
        /// A passphrase was offered for a device that has no wrapped record to open.
        case nothingToUnlock
        /// The passphrase did not open the record. Wrong passphrase, or an altered record, and
        /// this cannot tell which.
        case wrongPassphrase
        case storage(SecretStoreError)
    }

    private let keys: VaultKeyStore
    private let wrapped: WrappedKeyStore

    public init(keys: VaultKeyStore = VaultKeyStore(), wrapped: WrappedKeyStore = WrappedKeyStore()) {
        self.keys = keys
        self.wrapped = wrapped
    }

    public func state() -> State {
        if (try? keys.load()) ?? nil != nil { return .open }
        return wrapped.exists ? .locked : .absent
    }

    // MARK: - Creating

    /// Creates a vault and returns the passphrase that recovers it, **once**.
    ///
    /// The passphrase is returned rather than stored, and this is the only moment it exists.
    ///
    /// **Prefer `create(with:)` in the app.** `docs/VAULT.md` requires that no vault exist whose
    /// passphrase has not been shown and acknowledged, and this method creates one before anybody
    /// has seen anything: a process killed between the call and the screen leaves a vault with a
    /// passphrase that no longer exists anywhere. Generating first, showing, and only then
    /// creating closes that window, which is why the interface takes the two-step path and this
    /// convenience is left for tests and for callers with no screen to show.
    public func create() throws(VaultError) -> (key: SymmetricKey, passphrase: String) {
        guard let generated = BackupPassphrase.generate() else {
            throw .storage(.keychain(status: -1))
        }

        let passphrase = BackupPassphrase.grouped(generated)
        return (try create(with: passphrase), passphrase)
    }

    /// Creates a vault recoverable by a passphrase the caller already holds and has shown.
    ///
    /// Creation writes the wrapped record **before** the key. A key with no record is a device
    /// that works until it is replaced and then cannot be recovered by anybody; a record with no
    /// key is merely a device that must be unlocked, which is a state the app already handles.
    /// The bad order fails silently and the safe one fails visibly.
    ///
    /// The passphrase is canonicalised on the way in, so the grouped form that was displayed and
    /// the bare form both derive the same key. It is never stored in either form.
    @discardableResult
    public func create(with passphrase: String) throws(VaultError) -> SymmetricKey {
        do {
            let key = SymmetricKey(size: .bits256)
            try wrapped.save(try WrappedVaultKey.wrap(vaultKey: key, passphrase: passphrase))
            try keys.install(key)
            return key
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }
    }

    // MARK: - Unlocking

    /// Opens this device with a passphrase, and installs the key it recovers.
    public func unlock(with passphrase: String) throws(VaultError) {
        let record: Data?
        do {
            record = try wrapped.load()
        } catch {
            throw .storage(error)
        }

        guard let record else { throw .nothingToUnlock }

        do {
            let key = try WrappedVaultKey.unwrap(record, passphrase: passphrase)
            try keys.install(key)
        } catch is WrappedVaultKey.WrapError {
            throw .wrongPassphrase
        } catch {
            throw .storage(.keychain(status: -1))
        }
    }

    /// Replaces the passphrase, returning the new one.
    ///
    /// **This is not revocation and must never be offered as one.** It rewraps the same vault
    /// key, so anybody who captured the old record and knew the old passphrase keeps access
    /// forever. Responding to a compromise needs key rotation, which version 1 does not have.
    /// `docs/VAULT.md` says so, and this comment exists so the next person to read this method
    /// does not conclude otherwise from its convenience.
    public func replacePassphrase() throws(VaultError) -> String {
        guard let key = (try? keys.load()) ?? nil else { throw .nothingToUnlock }
        guard let passphrase = BackupPassphrase.generate() else {
            throw .storage(.keychain(status: -1))
        }

        do {
            try wrapped.save(try WrappedVaultKey.wrap(vaultKey: key, passphrase: passphrase))
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }

        return BackupPassphrase.grouped(passphrase)
    }

    // MARK: - Removing

    /// Forgets everything: the key on this device and the wrapped record.
    ///
    /// Only for erase, and only alongside deleting the accounts. On its own it would leave
    /// ciphertext that nothing can ever open again.
    public func destroy() throws(VaultError) {
        do {
            try keys.discard()
            try wrapped.delete()
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }
    }
}
