import Foundation
import OpenFactorCore

/// The app's store, with the sync setting read at the moment of each call.
///
/// `KeychainSecretStore` takes its sync setting at construction and never reads
/// `UserDefaults`, deliberately: a security core that reaches for global mutable state is
/// one an auditor has to chase across the project. Something still has to connect the
/// preference to the store, though, or an account added after the switch is flipped would
/// be written with the setting the app launched with.
///
/// This is that connection, and it lives in the app target where the preference does. It
/// builds a store per call rather than holding one, which costs four field copies and
/// removes a whole class of bug: there is no cached setting to go stale, so no view needs
/// rebuilding when the switch moves. The first attempt did rebuild the view tree, by
/// changing the root view's identity, and it dismissed the settings sheet out from under
/// the switch the user had just touched.
struct SyncAwareKeychainStore: SynchronizableSecretStore {

    /// Whether accounts should be offered to iCloud, **asked at the moment of the call**.
    ///
    /// A closure rather than the `UserDefaults` object itself. Storing one made this struct
    /// non-Sendable, which the compiler currently reports as a warning and Swift 6 will report
    /// as an error. It also states the dependency more honestly: this type needs one boolean,
    /// not a whole preferences database.
    private let syncEnabled: @Sendable () -> Bool

    /// Only tests pass a service. The default is the one the app uses, so no caller in the
    /// app can accidentally point at a different set of items.
    private let service: String?

    /// This device's vault key. Passed through to every store this builds, because a store
    /// without one reads ciphertext it cannot open.
    ///
    /// **The sync preference must not reach the vault key.** Turning sync off changes where
    /// account items are offered, and changes nothing about which key opens them: the key never
    /// syncs under any setting, and a device that lost its key when the switch moved would have
    /// its accounts made unreadable by a preference.
    private let vaultKeys: VaultKeyStore

    /// The wrapped vault key's store, so the sync switch can move it alongside the accounts.
    /// Held rather than rebuilt per call, because unlike the account store it carries no
    /// setting that can go stale: where the record lives is read from the Keychain each time.
    private let wrapped: WrappedKeyStore

    init(
        defaults: UserDefaults = .standard,
        service: String? = nil,
        vaultKeys: VaultKeyStore = VaultKeyStore(),
        wrapped: WrappedKeyStore = WrappedKeyStore()
    ) {
        self.wrapped = wrapped
        // Captured, not stored. The preference is still read on every call, which is the whole
        // point of this type: an account added after the switch moves inherits the new setting
        // without anything being rebuilt.
        syncEnabled = { defaults.bool(forKey: PreferenceKey.syncEnabled) }
        self.service = service
        self.vaultKeys = vaultKeys
    }

    private var store: KeychainSecretStore {
        let shouldSync = syncEnabled()
        let accessibility = SecretAccessibility.forSync(shouldSync)

        if let service {
            return KeychainSecretStore(
                service: service,
                accessibility: accessibility,
                synchronizable: shouldSync,
                vaultKeys: vaultKeys
            )
        }

        return KeychainSecretStore(
            accessibility: accessibility, synchronizable: shouldSync, vaultKeys: vaultKeys)
    }

    @discardableResult
    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        try store.add(account, color: color)
    }

    func records() throws(SecretStoreError) -> StoredRecords {
        try store.records()
    }

    func secret(for id: UUID) throws(SecretStoreError) -> Data {
        try store.secret(for: id)
    }

    func update(_ record: AccountRecord) throws(SecretStoreError) {
        try store.update(record)
    }

    func delete(id: UUID) throws(SecretStoreError) {
        try store.delete(id: id)
    }

    /// Moves the accounts **and the wrapped vault key** to the requested side.
    ///
    /// **The wrapped key was left behind for the whole life of this feature**, which the A4
    /// review found: `KeychainSecretStore.setSynchronizable` works through a query whose service
    /// is the accounts service, so nothing in the app ever touched
    /// `app.openfactor.vault.key`. Turning sync on offered iCloud Keychain the account
    /// ciphertext and kept the only means of reading it on one device, so replacing that device
    /// produced a phone full of unreadable accounts and a passphrase with nothing to unwrap.
    /// `docs/VAULT.md` had promised the opposite in its Sync section since before the code
    /// existed.
    ///
    /// **The key goes first when enabling and last when disabling**, so the intermediate state
    /// is always the safe one. Enabling: the means of reading arrives before, or with, the thing
    /// to read. Disabling: the accounts stop syncing before their key does, so no window exists
    /// where iCloud holds ciphertext whose key has already been withdrawn.
    ///
    /// A partial failure throws, and both halves are idempotent, so the remedy is to run it
    /// again rather than to reason about what got through.
    @discardableResult
    func setSynchronizable(_ shouldSync: Bool) throws(SecretStoreError) -> Int {
        // **Nothing moves until the wrapped key is known to be able to move.** Turning sync off
        // converts the accounts first and the record second, and that order is deliberate: the
        // reverse leaves a window with accounts in iCloud and no key to read them. But it means a
        // record that cannot convert throws with every account already local, while the
        // preference, which flips only on success, still reads on, so the switch claims iCloud
        // holds accounts it does not. A read that refuses before anything is written costs one
        // query and removes that state.
        try wrapped.precheckConversion()

        if shouldSync {
            try wrapped.setSynchronizable(true)
            return try store.setSynchronizable(true)
        }

        let converted = try store.setSynchronizable(false)
        try wrapped.setSynchronizable(false)
        return converted
    }

    func syncState() throws(SecretStoreError) -> SyncState {
        try store.syncState()
    }

    @discardableResult
    func migrateToDefaultAccessGroup() throws(SecretStoreError) -> Int {
        try store.migrateToDefaultAccessGroup()
    }
}
