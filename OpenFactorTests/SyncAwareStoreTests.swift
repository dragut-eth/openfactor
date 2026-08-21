import Foundation
import Security
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// The one job of `SyncAwareKeychainStore` is that an account added after the switch moves
/// is written the way the switch says. The first version of this feature got that wrong in
/// a way no test would have caught, because it read the preference once at launch.
@Suite("Sync aware store")
struct SyncAwareStoreTests {

    /// A defaults suite of its own, so nothing here touches the real preferences and the
    /// tests do not depend on each other's order.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "app.openfactor.tests.\(UUID().uuidString)")!
    }

    private func account() -> OTPAccount {
        OTPAccount(
            issuer: "GitHub",
            name: "octocat",
            secret: Data("12345678901234567890".utf8),
            generator: .totp(.standard)
        )
    }

    /// Read back without going through the store, so the assertion is about what is on the
    /// device rather than about what the store believes it wrote.
    private func rawItem(service: String) -> [String: Any]? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnAttributes as String: true,
            ] as CFDictionary,
            &result
        )

        guard status == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    /// Every item for a service, so a test can assert about the mix rather than about
    /// whichever one the Keychain happens to return first.
    private func rawItems(service: String) -> [[String: Any]] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
            ] as CFDictionary,
            &result
        )

        guard status == errSecSuccess else { return [] }
        return result as? [[String: Any]] ?? []
    }

    private func cleanUp(service: String) {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ] as CFDictionary
        )
    }


    /// A vault key of its own, so this suite exercises the sync preference rather than the
    /// vault. The preference must never reach the key: turning sync off changes where items are
    /// offered and nothing about which key opens them.
    private func makeVault() throws -> VaultKeyStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        _ = try keys.create()
        return keys
    }

    @Test("With sync off, a new account is device only and not offered to iCloud")
    func addsUnsyncedWhenPreferenceIsOff() throws {
        let service = "app.openfactor.tests.\(UUID().uuidString)"
        defer { cleanUp(service: service) }

        let defaults = makeDefaults()
        defaults.set(false, forKey: PreferenceKey.syncEnabled)

        try SyncAwareKeychainStore(
            defaults: defaults, service: service, vaultKeys: try makeVault()
        ).add(account(), color: .blue)

        let item = try #require(rawItem(service: service))
        #expect(item[kSecAttrSynchronizable as String] as? Bool != true)
        #expect(
            item[kSecAttrAccessible as String] as? String
                == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        )
    }

    /// The regression this type exists to prevent. The preference is read at the moment of
    /// the call, so an account added after the switch moves inherits the new setting
    /// without anything being rebuilt or reconstructed.
    @Test("A change to the preference reaches the very next account added")
    func followsThePreferenceWithoutBeingRebuilt() throws {
        let service = "app.openfactor.tests.\(UUID().uuidString)"
        defer { cleanUp(service: service) }

        let defaults = makeDefaults()
        defaults.set(false, forKey: PreferenceKey.syncEnabled)

        let store = SyncAwareKeychainStore(
            defaults: defaults, service: service, vaultKeys: try makeVault())
        try store.add(account(), color: .blue)

        // The same store instance, deliberately. Nothing is re-created here.
        defaults.set(true, forKey: PreferenceKey.syncEnabled)
        try store.add(
            OTPAccount(
                issuer: "Fastmail",
                name: "octocat",
                secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)
            ),
            color: .green
        )

        // Exactly one of the two is synchronizable: the one added after the switch moved.
        // The first is untouched, which is the correct behaviour here. Converting what is
        // already stored is `setSynchronizable`'s job, and the settings screen calls it.
        let items = rawItems(service: service)
        #expect(items.count == 2)
        #expect(items.filter { $0[kSecAttrSynchronizable as String] as? Bool == true }.count == 1)

        // And both are still readable, whatever their sync state.
        #expect(try store.records().readable.count == 2)
    }

    /// **Nothing moves until the wrapped key is known to be able to move.** Turning sync off
    /// converts the accounts first and the wrapped record second, which is the safe order: the
    /// reverse leaves a window with accounts in iCloud and no key to read them. But it means a
    /// wrapped record that cannot convert throws after every account is already local, while the
    /// preference, which flips only on success, still reads on. The switch then claims iCloud
    /// holds accounts it does not.
    ///
    /// Remove the pre-flight and this goes red, with the accounts converted.
    @Test("A wrapped record that cannot convert stops the accounts from moving")
    func accountsDoNotMoveWhenTheWrappedRecordCannot() throws {
        let service = "app.openfactor.tests.\(UUID().uuidString)"
        let wrappedService = "app.openfactor.tests.key.\(UUID().uuidString)"
        defer { cleanUp(service: service) }

        let wrapped = WrappedKeyStore(service: wrappedService)
        defer {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: wrappedService,
                    kSecUseDataProtectionKeychain as String: true,
                    kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                ] as CFDictionary)
        }

        let defaults = makeDefaults()
        defaults.set(true, forKey: PreferenceKey.syncEnabled)
        let store = SyncAwareKeychainStore(
            defaults: defaults, service: service, vaultKeys: try makeVault(), wrapped: wrapped)
        _ = try store.add(account(), color: .teal)

        // Two wrapped records, so the conversion cannot succeed either way.
        try wrapped.save(Data("this device's record".utf8))
        let theirs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: wrappedService,
            kSecAttrAccount as String: "wrapped",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: Data("the other vault's record".utf8),
        ]
        SecItemAdd(theirs as CFDictionary, nil)

        #expect(throws: SecretStoreError.twinnedRecord) { _ = try store.setSynchronizable(false) }
        #expect(
            rawItem(service: service)?[kSecAttrSynchronizable as String] as? Bool == true,
            "the accounts are where they were, so the switch is not left overstating protection")
    }

    @Test("Turning sync on converts what is already stored")
    func convertsExistingAccounts() throws {
        let service = "app.openfactor.tests.\(UUID().uuidString)"
        defer { cleanUp(service: service) }

        let defaults = makeDefaults()
        defaults.set(false, forKey: PreferenceKey.syncEnabled)

        let store = SyncAwareKeychainStore(
            defaults: defaults, service: service, vaultKeys: try makeVault())
        try store.add(account(), color: .blue)

        #expect(try store.setSynchronizable(true) == 1)

        let item = try #require(rawItem(service: service))
        #expect(item[kSecAttrSynchronizable as String] as? Bool == true)
    }
}
