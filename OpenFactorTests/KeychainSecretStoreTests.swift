import Foundation
import Security
import Testing

@testable import OpenFactorCore

/// The assertions that only mean something against a real Keychain.
///
/// **These are skipped by `swift test`.** An unsigned test bundle has no entitlement for
/// the data protection Keychain, so there is nothing here to assert against. They run
/// only inside a host application, which is why this suite lives in the hosted target
/// for why the legacy Keychain is not an acceptable stand in.
///
/// The protection class on a stored secret is the single most consequential line in this
/// project, and until these run it is unverified. That is written down in `HANDOFF.md`
/// and in the checklist for gate A1.
@Suite("Keychain storage")
struct KeychainSecretStoreTests {

    private func makeStore(
        accessibility: SecretAccessibility = .whenUnlockedThisDeviceOnly,
        synchronizable: Bool = false
    ) -> KeychainSecretStore {
        // Its own directory, so no two stores share a vault key and none is written into the
        // application support directory of whatever process runs the tests.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        _ = try? keys.create()

        return KeychainSecretStore(
            service: "app.openfactor.tests.\(UUID().uuidString)",
            accessibility: accessibility,
            synchronizable: synchronizable,
            vaultKeys: keys
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

    /// The stored blob itself, which is what a sibling gets. `rawItem` returns attributes and
    /// deliberately not this.
    private func rawValue(from store: KeychainSecretStore) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: store.service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
            ] as CFDictionary,
            &result
        )
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// **The defence gate E1 exists for, run rather than read.**
    ///
    /// E1 measured that a Keychain access group is not a boundary between two apps of the same
    /// team: a sibling can read this app's items, including from the default group most people
    /// assume is private. That measurement cannot be a test, because it needs a second signed
    /// app, and `docs/audits/E/README.md` says so.
    ///
    /// **What the sibling then finds can be a test, and this is it.** The whole vault design is
    /// the answer to E1, and until now nothing looked at the bytes it produces. Every other
    /// assertion in this suite reads the item's *attributes*; `rawItem` does not even ask for the
    /// data. So this reads the blob the sibling would read and asserts none of the three things
    /// worth stealing is legible in it.
    ///
    /// A reviewer said the platform assumptions in this project were prose they could not run.
    /// This one they can.
    @Test("A sibling reading the raw item finds nothing legible in it")
    func theStoredBytesAreOpaque() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        // Distinctive strings, so a match cannot be a coincidence and a miss cannot be luck.
        let issuer = "AcmeIssuerZQX"
        let name = "distinctive-holder-4718"
        let secret = Data("NOTASECRETBUTLOOKSLIKEONE".utf8)

        try store.add(
            OTPAccount(issuer: issuer, name: name, secret: secret, generator: .totp(.standard)),
            color: .blue)

        let stored = try #require(rawValue(from: store), "there should be an item to read")

        // **Not vacuous.** A store that wrote nothing, or wrote an empty blob, would pass every
        // assertion below without meaning any of them.
        #expect(stored.count > 32, "the item must actually carry a sealed record")

        // **And the search itself has to be capable of finding something.** Three assertions
        // that a needle is absent prove nothing unless the same search finds a needle that is
        // present. The record's magic is the one thing deliberately in the clear.
        #expect(
            stored.range(of: Data("OFV1".utf8)) != nil,
            "the search must be able to match, or the three below are decoration")

        #expect(stored.range(of: Data(issuer.utf8)) == nil, "the issuer is legible in the item")
        #expect(stored.range(of: Data(name.utf8)) == nil, "the account name is legible")
        #expect(stored.range(of: secret) == nil, "the shared secret is legible")

        // And the store itself must still be able to read what it wrote, or opacity would be
        // indistinguishable from corruption.
        let records = try store.records()
        #expect(records.readable.count == 1)
        #expect(records.readable.first?.metadata.issuer == issuer)
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
            group?.hasSuffix("dev.openfactor.shared") == true,
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
