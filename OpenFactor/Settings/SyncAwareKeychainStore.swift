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

    /// Where the preference is read from. Injectable so tests do not touch the real
    /// defaults, and so the suite can run in any order without leaking state.
    private let defaults: UserDefaults

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

    init(
        defaults: UserDefaults = .standard,
        service: String? = nil,
        vaultKeys: VaultKeyStore = VaultKeyStore()
    ) {
        self.defaults = defaults
        self.service = service
        self.vaultKeys = vaultKeys
    }

    private var store: KeychainSecretStore {
        let shouldSync = defaults.bool(forKey: PreferenceKey.syncEnabled)
        let accessibility: SecretAccessibility =
            shouldSync ? .whenUnlocked : .whenUnlockedThisDeviceOnly

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

    @discardableResult
    func setSynchronizable(_ shouldSync: Bool) throws(SecretStoreError) -> Int {
        try store.setSynchronizable(shouldSync)
    }

    func syncState() throws(SecretStoreError) -> SyncState {
        try store.syncState()
    }

    @discardableResult
    func migrateToDefaultAccessGroup() throws(SecretStoreError) -> Int {
        try store.migrateToDefaultAccessGroup()
    }
}
