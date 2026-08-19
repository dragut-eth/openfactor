import CryptoKit
import Foundation

/// What state this device's vault is in, and what can be done about it.
///
/// The whole of the vault's lifecycle is here rather than in a view, because the decisions are
/// about storage and the same ones apply on a watch, where the interface is entirely different.
///
/// ## The states, and why telling them apart matters
///
/// | Key on this device | Wrapped record present | State |
/// | --- | --- | --- |
/// | yes | either | `open` |
/// | no | no | `absent`, no vault has ever existed |
/// | no | yes | `locked`, this device needs the passphrase it was already given |
/// | unknown | unknown | `unavailable`, the store could not be read and nothing is guessed |
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
        /// The store could not be read, so which of the three above is true is unknown.
        ///
        /// **Not a fourth kind of vault: a refusal to guess.** This used to collapse into
        /// `absent`, because `exists` was `(try? load()) != nil`, and absent is the one state
        /// whose remedy is destructive: it offers to create a vault, and creating one overwrites
        /// the wrapped record every stored account depends on. A Keychain read that fails while
        /// the device is locked, or under any transient error, therefore led the interface to
        /// offer total loss as its only suggestion. Gate A4 found it.
        case unavailable
    }

    public enum VaultError: Error, Equatable, Sendable {
        /// A passphrase was offered for a device that has no wrapped record to open.
        case nothingToUnlock
        /// The passphrase did not open the record. Wrong passphrase, or an altered record, and
        /// this cannot tell which.
        case wrongPassphrase
        /// The record is not one this build can read: not the right magic, or an iteration count
        /// outside the range this version accepts.
        ///
        /// **Separated from `wrongPassphrase` because the remedy is opposite.** Both of these are
        /// decided before any derivation runs, so no passphrase could have opened this record.
        /// Reporting them as a wrong passphrase sends somebody to try their passphrase again,
        /// and again, against a record written by a newer version of this app or by something
        /// else entirely.
        case recordNotUnderstood
        /// A vault already exists on this device, or one is arriving, so creating would replace
        /// the record that opens the accounts already stored.
        case alreadyExists
        case storage(SecretStoreError)
    }

    private let keys: VaultKeyStore
    private let wrapped: any WrappedRecordStore

    public init(
        keys: VaultKeyStore = VaultKeyStore(),
        wrapped: any WrappedRecordStore = WrappedKeyStore()
    ) {
        self.keys = keys
        self.wrapped = wrapped
    }

    public func state() -> State {
        if (try? keys.load()) ?? nil != nil { return .open }

        // `load()` rather than `exists`, so a read that fails is told apart from a read that
        // finds nothing. See `State.unavailable`.
        do {
            return try wrapped.load() != nil ? .locked : .absent
        } catch {
            return .unavailable
        }
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
    ///
    /// **Refuses if anything is already there.** `save` replaces the record it finds, so without
    /// this check a creation racing an arriving wrap silently overwrote the credential that
    /// opened every account already stored. The window is this project's own measured half hour
    /// of iCloud Keychain propagation, and the tap that triggers it is the ordinary one on a
    /// second device set up the same day. Two reviews found it independently.
    ///
    /// A store that cannot be read refuses too. The point of the check is not to find a record;
    /// it is to decline to overwrite what it cannot see.
    @discardableResult
    public func create(with passphrase: String) throws(VaultError) -> SymmetricKey {
        switch state() {
        case .open, .locked: throw .alreadyExists
        case .unavailable: throw .storage(.keychain(status: errSecNotAvailable))
        case .absent: break
        }

        let key = SymmetricKey(size: .bits256)
        let created: Bool

        do {
            // **`addIfAbsent` rather than `save`, and that is the whole of the fix.** The check
            // above is hundreds of milliseconds before this line: `wrap` runs 600,000 rounds of
            // PBKDF2 in between, and iCloud can deliver the real record inside that window. `save`
            // replaces what it finds, so creation used to overwrite the wrapped key that opens
            // every account already stored. Two engines walked that out independently in round
            // two, and the test written for the check could not see it, because its record never
            // changed while the derivation ran.
            created = try wrapped.addIfAbsent(
                try WrappedVaultKey.wrap(vaultKey: key, passphrase: passphrase))
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }

        // Outside the catch on purpose: a refusal is this method's own answer, and the block
        // above turns anything it does not recognise into `.storage`, which would bury it.
        guard created else { throw .alreadyExists }

        do {
            try keys.install(key)
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }
        return key
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
        } catch let error as WrappedVaultKey.WrapError {
            // The two that are decided before any derivation runs are not a passphrase problem
            // and must not be reported as one. See `VaultError.recordNotUnderstood`.
            switch error {
            case .notAWrappedKey, .iterationsOutOfRange: throw .recordNotUnderstood
            case .wrongPassphrase: throw .wrongPassphrase
            // A CommonCrypto failure is this device's problem, not a mistyped character, and
            // telling somebody to check their typing for it is the same category error in
            // miniature. A review noticed it in the fix for the larger one.
            case .derivationFailed: throw .storage(.keychain(status: -1))
            }
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
    /// **Not public.** A review asked for it to go entirely; it is kept because the tests for
    /// the two-step path still need a one-call way to reach a replaced state, and made internal
    /// so no caller outside this package can pick the footgun by accident. The app uses
    /// `prepareReplacementPassphrase()` and `replacePassphrase(with:)`.
    func replacePassphrase() throws(VaultError) -> String {
        let passphrase = try prepareReplacementPassphrase()
        try replacePassphrase(with: passphrase)
        return passphrase
    }

    /// Generates a replacement passphrase and stores nothing.
    ///
    /// **The two-step shape, for the same reason creation has one.** `replacePassphrase` saved
    /// the new wrap and returned the string afterwards, so a crash or a torn-down view between
    /// the save and the screen left a vault whose only recovery credential nobody had ever seen,
    /// on a device that kept working perfectly and so signalled nothing. This project had already
    /// learned that lesson once and written the reasoning above `create(with:)`; nobody applied
    /// it to replacement until a review did.
    ///
    /// The one-shot above is kept for tests and for callers with no screen, exactly as `create()`
    /// is, and carries the same warning.
    public func prepareReplacementPassphrase() throws(VaultError) -> String {
        guard (try? keys.load()) ?? nil != nil else { throw .nothingToUnlock }
        guard let generated = BackupPassphrase.generate() else {
            throw .storage(.keychain(status: -1))
        }
        return BackupPassphrase.grouped(generated)
    }

    /// Rewraps the vault key under a passphrase that has already been shown and acknowledged.
    public func replacePassphrase(with passphrase: String) throws(VaultError) {
        guard let key = (try? keys.load()) ?? nil else { throw .nothingToUnlock }

        do {
            try wrapped.save(try WrappedVaultKey.wrap(vaultKey: key, passphrase: passphrase))
        } catch let error as SecretStoreError {
            throw .storage(error)
        } catch {
            throw .storage(.keychain(status: -1))
        }
    }

    #if DEBUG
        /// Forgets this device's key and leaves the wrapped record, which is exactly the
        /// `locked` state.
        ///
        /// **A development tool, compiled out of any build that is not Debug.** It exists so the
        /// unlock screen can be looked at without contriving a second device: that screen is the
        /// ordinary state of a new iPhone or a reinstall, and it was otherwise unreachable on a
        /// phone that had already been set up.
        ///
        /// Nothing is destroyed. The accounts stay, sealed, and the passphrase still opens them.
        public func discardKeyForDebug() throws(VaultError) {
            do {
                try keys.discard()
            } catch let error as SecretStoreError {
                throw .storage(error)
            } catch {
                throw .storage(.keychain(status: -1))
            }
        }
    #endif

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
