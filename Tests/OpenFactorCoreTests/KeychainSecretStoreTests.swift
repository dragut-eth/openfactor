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
/// project, and until these run it is unverified. That is written down in `HANDOFF.md`
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

    // MARK: - Turning sync on and off

    /// The claim this method makes about itself: an account can be converted without its
    /// secret being read, so the secret never enters this process and there is no moment
    /// where it exists only in memory.
    @Test("Turning sync on converts accounts in place and keeps the secret intact")
    func syncConversionPreservesSecrets() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let record = try store.add(account(), color: .blue)
        let secretBefore = try store.secret(for: record.id)

        #expect(try store.setSynchronizable(true) == 1)

        let item = try #require(rawItem(from: store))
        #expect(item[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(try store.secret(for: record.id) == secretBefore)
        #expect(try store.records().readable.count == 1, "The account must still be listed")
    }

    /// A synchronizable item cannot be device only, by definition. Turning sync on
    /// therefore weakens the protection class, and that has to be visible rather than a
    /// side effect nobody wrote down.
    @Test("Turning sync on weakens the protection class, and off restores it")
    func syncChangesTheProtectionClass() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)

        try store.setSynchronizable(true)
        var item = try #require(rawItem(from: store))
        #expect(item[kSecAttrAccessible as String] as? String == (kSecAttrAccessibleWhenUnlocked as String))

        try store.setSynchronizable(false)
        item = try #require(rawItem(from: store))
        #expect(
            item[kSecAttrAccessible as String] as? String
                == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String),
            "Turning sync off must put the stronger class back, not leave it weakened"
        )
        #expect(item[kSecAttrSynchronizable as String] as? Bool != true)
    }

    /// A partial failure means the whole conversion runs again, so running it twice must
    /// be harmless and must not report work it did not do.
    @Test("Converting twice changes nothing the second time")
    func syncConversionIsIdempotent() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        try store.add(account(), color: .blue)

        #expect(try store.setSynchronizable(true) == 1)
        #expect(try store.setSynchronizable(true) == 0, "Nothing was left to convert")
        #expect(try store.records().readable.count == 1)
    }

    @Test("Converting an empty store is not an error")
    func syncConversionWithNoAccounts() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        #expect(try store.setSynchronizable(true) == 0)
    }

    @Test("Every account is converted, not just the first")
    func syncConversionCoversEveryAccount() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        for index in 0..<5 {
            try store.add(
                OTPAccount(
                    issuer: "Service \(index)",
                    name: "someone",
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)
                ),
                color: .blue
            )
        }

        #expect(try store.setSynchronizable(true) == 5)
        #expect(try store.records().readable.count == 5)
    }

    /// Two stores with different service names must not see each other's accounts. This
    /// is what keeps a test, or a future second target, from reading the real app's data.

    /// The assertion behind "try again". Gate A2, F13 found it missing: the idempotency
    /// test only re-ran a fully converted store, which proves the no-op case and says
    /// nothing about the case the claim actually exists for, a conversion that stopped
    /// half way. This builds that state by hand and checks the re-run finishes the job
    /// without disturbing what was already done.
    @Test("Re-running a half finished conversion converts exactly the remainder")
    func repairsAPartialConversion() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        for issuer in ["GitHub", "Fastmail", "Proton"] {
            try store.add(
                OTPAccount(
                    issuer: issuer,
                    name: "octocat",
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)
                ),
                color: .blue
            )
        }

        let before = try store.records().readable
        #expect(before.count == 3)

        // Convert one item by hand, which is what a conversion killed part way leaves.
        let first = try #require(before.first)
        let converted = SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: store.service,
                kSecAttrAccount as String: first.id.uuidString,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: false,
            ] as CFDictionary,
            [
                kSecAttrSynchronizable as String: true,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ] as CFDictionary
        )
        #expect(converted == errSecSuccess)

        // The re-run touches the two that are left, and not the one already done.
        #expect(try store.setSynchronizable(true) == 2)

        let state = try store.syncState()
        #expect(state.synced.count == 3)
        #expect(state.local.isEmpty)

        // And nothing lost its metadata or its secret on the way through.
        let after = try store.records().readable
        #expect(Set(after.map(\.metadata.issuer)) == ["GitHub", "Fastmail", "Proton"])
        #expect(try store.secret(for: first.id) == Data("12345678901234567890".utf8))
    }

    @Test("The sync state reports which accounts are where")
    func reportsSyncState() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        #expect(try store.syncState() == SyncState(synced: [], local: []))

        let record = try store.add(account(), color: .blue)
        var state = try store.syncState()
        #expect(state.local == [record.id])
        #expect(state.synced.isEmpty)
        #expect(!state.isMixed)

        try store.setSynchronizable(true)
        state = try store.syncState()
        #expect(state.synced == [record.id])
        #expect(state.local.isEmpty)
        #expect(!state.isMixed)
    }

    /// A mixture is not corruption, and the interface has to be able to see it: it is what
    /// a half finished conversion looks like, and what a device holds when an account
    /// arrives from elsewhere while its own switch is off. Gate A2, F12.
    @Test("A half converted store reports as mixed")
    func reportsAMixedStore() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        let first = try store.add(account(), color: .blue)
        try store.setSynchronizable(true)
        let second = try store.add(
            OTPAccount(
                issuer: "Fastmail",
                name: "octocat",
                secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)
            ),
            color: .green
        )

        let state = try store.syncState()
        #expect(state.synced == [first.id])
        #expect(state.local == [second.id])
        #expect(state.isMixed)
    }

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
