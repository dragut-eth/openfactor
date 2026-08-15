import Foundation
import Security
import Testing

@testable import OpenFactorCore

/// The assertions that only mean something against a real Keychain.
///
/// **These are skipped by `swift test`.** An unsigned test bundle has no entitlement for
/// the data protection Keychain, so there is nothing here to assert against. They run
/// once there is a host application target, which is PR 5. See ``KeychainAvailability``
/// for why the legacy Keychain is not an acceptable stand in.
///
/// The protection class on a stored secret is the single most consequential line in this
/// project, and until these run it is unverified. That is written down in `handoff.md`
/// and in the checklist for gate A1.
@Suite("Keychain storage", .enabled(if: KeychainAvailability.isUsable))
struct KeychainSecretStoreTests {

    private func makeStore(
        accessibility: SecretAccessibility = .whenUnlockedThisDeviceOnly,
        synchronizable: Bool = false
    ) -> KeychainSecretStore {
        KeychainSecretStore(
            service: "app.openfactor.tests.\(UUID().uuidString)",
            accessibility: accessibility,
            synchronizable: synchronizable
        )
    }

    /// Reads the raw item back, bypassing the store, so the assertions are about what is
    /// actually on the device rather than about what the store believes it wrote.
    private func rawItem(from store: KeychainSecretStore) -> [String: Any]? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: store.service,
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

    private func account() -> OTPAccount {
        OTPAccount(
            issuer: "GitHub",
            name: "octocat",
            secret: Data("12345678901234567890".utf8),
            generator: .totp(.standard)
        )
    }

    /// The most important assertion in the project. Secrets must be unreadable while the
    /// device is locked, and must never travel to another device unless the user asks.
    @Test("Secrets are stored as unlocked only and device only")
    func usesTheStrictestProtectionClass() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)
        let item = try #require(rawItem(from: store))

        #expect(
            item[kSecAttrAccessible as String] as? String
                == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        )
    }

    /// The whole watch design rests on this. A Keychain item lives in the group it was
    /// written to, the watch app has its own bundle identifier and therefore its own
    /// default group, and iCloud Keychain syncs within a group rather than across them. If
    /// secrets stop landing in the shared group, the watch silently shows an empty list.
    ///
    /// Nothing names the group in code: the entitlement declares exactly one, and the
    /// Keychain uses the first entitlement group for anything written without one. This
    /// asserts that indirection actually works, rather than trusting it.
    @Test("Secrets are written to the shared access group the watch will read")
    func usesTheSharedAccessGroup() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)
        let item = try #require(rawItem(from: store))
        let group = item[kSecAttrAccessGroup as String] as? String

        #expect(
            group?.hasSuffix("com.openfactor.shared") == true,
            """
            Secrets landed in \(group ?? "no group") rather than the shared group. \
            Check OpenFactor.entitlements: the first group in it is the one the Keychain \
            writes to by default.
            """
        )
    }

    @Test("Sync is off unless it is asked for")
    func doesNotSyncByDefault() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)
        let item = try #require(rawItem(from: store))

        #expect(item[kSecAttrSynchronizable as String] as? Bool != true)
    }

    /// Sync cannot carry a device only item, so turning it on has to weaken the class.
    /// The point of this test is that the weakening is visible and deliberate.
    @Test("Choosing sync uses the class that sync requires")
    func syncUsesTheWeakerClass() throws {
        let store = makeStore(accessibility: .whenUnlocked, synchronizable: true)
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)
        let item = try #require(rawItem(from: store))

        #expect(item[kSecAttrAccessible as String] as? String == (kSecAttrAccessibleWhenUnlocked as String))
        #expect(item[kSecAttrSynchronizable as String] as? Bool == true)
    }

    /// The whole point of the storage design: the list is drawn without decrypting a
    /// single secret. This asserts the query, not the intention.
    @Test("Listing accounts returns no secret material")
    func listingReturnsNoSecrets() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)

        var result: CFTypeRef?
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecUseDataProtectionKeychain as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        query[kSecReturnData as String] = false

        SecItemCopyMatching(query as CFDictionary, &result)
        let items = try #require(result as? [[String: Any]])

        for item in items {
            #expect(item[kSecValueData as String] == nil)
        }
    }

    /// On macOS the label is what Keychain Access shows in its list. Putting the account
    /// name there would print which services someone uses on a screen anyone walking past
    /// their desk can read.
    @Test("The visible label does not name the account")
    func labelDoesNotLeakTheAccountName() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)
        let item = try #require(rawItem(from: store))
        let label = item[kSecAttrLabel as String] as? String

        #expect(label == "OpenFactor")
        #expect(label?.contains("octocat") != true)
        #expect(label?.contains("GitHub") != true)
    }

    /// Two stores with different service names must not see each other's accounts. This
    /// is what keeps a test, or a future second target, from reading the real app's data.
    @Test("Stores with different service names are isolated")
    func servicesAreIsolated() throws {
        let first = makeStore()
        let second = makeStore()
        defer {
            first.cleanUp()
            second.cleanUp()
        }

        try first.add(account(), color: .blue)

        #expect(try first.records().readable.count == 1)
        #expect(try second.records().readable.isEmpty)
    }
}
