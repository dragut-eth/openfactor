import Foundation
import Security
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// Whether the wrapped vault key follows the accounts between iCloud and this device.
///
/// **This is the defect that loses every account**, found by two engines independently in gate
/// A4. `WrappedKeyStore` was created with `synchronizable: false`, nothing ever changed it, and
/// `KeychainSecretStore.setSynchronizable` works through a query whose service is the accounts
/// service. So turning sync on offered iCloud Keychain the ciphertext and kept the only means of
/// reading it on one device. Replacing that device produced every account present and unreadable,
/// with the passphrase having nothing to unwrap.
///
/// `docs/VAULT.md` promised the opposite in its Sync section, and the property's own comment said
/// it follows the account items. Neither was true, which is why this file asserts it rather than
/// leaving it to prose.
///
/// These tests need the real Keychain and are skipped where it is unavailable, which is the same
/// rule the other hosted suites follow.
@Suite("Wrapped key sync")
struct WrappedKeySyncTests {

    private func makeStore() -> WrappedKeyStore {
        WrappedKeyStore(service: "app.openfactor.tests.key.\(UUID().uuidString)")
    }

    /// Read back outside the store, so the assertion is about what the Keychain holds rather
    /// than about what the store believes it wrote.
    private func synchronizableFlag(of store: WrappedKeyStore) -> Bool? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "wrapped",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let attributes = result as? [String: Any]
        else { return nil }
        return attributes[kSecAttrSynchronizable as String] as? Bool
    }

    /// Every record under this service, so a twin is visible rather than hidden behind
    /// `kSecMatchLimitOne`.
    private func recordCount(of store: WrappedKeyStore) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let items = result as? [[String: Any]]
        else { return 0 }
        return items.count
    }

    // MARK: - The defect itself

    @Test("Turning sync on moves the wrapped key too")
    func syncOnMovesTheKey() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.save(Data("a wrapped key".utf8))
        #expect(synchronizableFlag(of: store) == false, "created device-only")

        #expect(try store.setSynchronizable(true))
        #expect(
            synchronizableFlag(of: store) == true,
            "the key must follow the accounts, or losing the phone loses the vault")
    }

    @Test("Turning sync off brings it back")
    func syncOffBringsItBack() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.save(Data("a wrapped key".utf8))
        #expect(try store.setSynchronizable(true))
        #expect(try store.setSynchronizable(false))
        #expect(synchronizableFlag(of: store) == false)
    }

    @Test("The record survives the move, byte for byte")
    func theRecordSurvivesTheMove() throws {
        let store = makeStore()
        defer { try? store.delete() }

        let record = Data("the only route back into the vault".utf8)
        try store.save(record)
        #expect(try store.setSynchronizable(true))

        #expect(try store.load() == record, "a move must never lose the record")
    }

    /// A device with no vault has nothing to move, which is not an error. The switch must work
    /// on a fresh install.
    @Test("Converting nothing is not an error")
    func convertingNothingIsFine() throws {
        let store = makeStore()
        #expect(try store.setSynchronizable(true) == false)
    }

    /// Run twice on purpose. A partial failure is recovered by running the whole thing again,
    /// so the second run must be harmless.
    @Test("Converting twice is harmless")
    func convertingIsIdempotent() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.save(Data("a wrapped key".utf8))
        #expect(try store.setSynchronizable(true))
        #expect(try store.setSynchronizable(true) == false, "already there")
        #expect(synchronizableFlag(of: store) == true)
        #expect(recordCount(of: store) == 1)
    }

    // MARK: - The twin, which the fix above makes reachable

    /// **The paired defect.** `kSecAttrSynchronizable` is part of a Keychain item's primary key,
    /// so an add whose flag differs from the existing record's does not collide: it succeeds and
    /// leaves two records. `load` then picks between them unspecified, and a correct passphrase
    /// can fail against the wrong one.
    ///
    /// This could not fire before, only because nothing ever made the record synchronizable.
    /// Fixing the sync gap is exactly what creates the differing flag, which is why the two
    /// changes had to land together and why this test exists.
    @Test("Saving after a sync change updates the record rather than twinning it")
    func savingAfterASyncChangeDoesNotTwin() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.save(Data("first".utf8))
        #expect(try store.setSynchronizable(true))

        // The store still believes it writes device-only records; the Keychain now holds a
        // synchronizable one. This is the passphrase-change path on a device whose preference
        // moved, and the shape that used to produce two records.
        try store.save(Data("second".utf8))

        #expect(recordCount(of: store) == 1, "two records under one identifier is the twin case")
        #expect(try store.load() == Data("second".utf8))
    }

    /// A passphrase change must not relocate the only recovery record. Where it lives is the
    /// sync switch's decision, and saving a new wrap is not that decision.
    @Test("Saving does not move the record between iCloud and this device")
    func savingDoesNotRelocateTheRecord() throws {
        let store = makeStore()
        defer { try? store.delete() }

        try store.save(Data("first".utf8))
        #expect(try store.setSynchronizable(true))
        #expect(synchronizableFlag(of: store) == true)

        try store.save(Data("second".utf8))
        #expect(
            synchronizableFlag(of: store) == true,
            "a passphrase change must not withdraw the record from iCloud")
    }

    // MARK: - The twin pair, against the real Keychain

    /// Writes a second record under the opposite flag, which is what iCloud delivering a twin
    /// does: `kSecAttrSynchronizable` is part of the primary key, so the add succeeds beside the
    /// existing record rather than colliding with it.
    private func plantTwin(_ record: Data, in store: WrappedKeyStore) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "wrapped",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: record,
        ]
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    private func deleteBothFlags(of store: WrappedKeyStore) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// **The adapter half of the round-four coverage gap.** `candidates()` had no test anywhere
    /// that executed the Keychain implementation, while `unlock`'s whole resolution of the twin
    /// case depends on it returning both records with the right flags.
    @Test("Candidates returns both twins, each under its own flag")
    func candidatesSeesBothTwins() throws {
        let store = makeStore()
        defer { deleteBothFlags(of: store) }

        try store.save(Data("device-only wrap".utf8))
        plantTwin(Data("synced wrap".utf8), in: store)
        #expect(recordCount(of: store) == 2, "the premise: a real twin pair in the Keychain")

        let found = try store.candidates()
        #expect(found.count == 2)
        #expect(
            Set(found.map(\.isSynchronizable)) == [false, true],
            "one under each flag, so unlock can try both")
        #expect(
            Set(found.map(\.record)) == [Data("device-only wrap".utf8), Data("synced wrap".utf8)])
    }

    /// **A replacement written into a twin pair would update one record unspecified**, which can
    /// overwrite the wrong vault's only recovery credential and propagate through iCloud. The
    /// real store must refuse, and the refusal must leave both records exactly as they were.
    /// Remove the `countingBothFlags` guard from `save` and this goes red.
    @Test("Saving into a twin pair is refused and touches nothing")
    func savingIntoTwinsIsRefused() throws {
        let store = makeStore()
        defer { deleteBothFlags(of: store) }

        try store.save(Data("device-only wrap".utf8))
        plantTwin(Data("synced wrap".utf8), in: store)

        #expect(throws: SecretStoreError.twinnedRecord) {
            try store.save(Data("a replacement that cannot name its target".utf8))
        }

        let after = try store.candidates()
        #expect(after.count == 2, "both records survived the refusal")
        #expect(
            Set(after.map(\.record)) == [Data("device-only wrap".utf8), Data("synced wrap".utf8)],
            "byte for byte")
    }

    /// **The sync preference is a question asked at each write, not a launch-time snapshot.**
    /// Held as a `Bool`, the store wrote every wrap under the preference as it stood when the
    /// app started, so enabling sync and creating a vault in the same session wrote the wrap
    /// device-only while every new account synced.
    @Test("A write follows the preference as it stands, not as it started")
    func theFlagIsAskedAtWriteTime() throws {
        let preference = LockedFlag()
        let store = WrappedKeyStore(
            service: "app.openfactor.tests.key.\(UUID().uuidString)",
            synchronizable: { preference.value })
        defer { deleteBothFlags(of: store) }

        preference.value = true
        _ = try store.addIfAbsent(Data("created after the switch moved".utf8))

        #expect(
            synchronizableFlag(of: store) == true,
            "the wrap follows the switch that already reads on")
    }
}

/// A mutable flag the `@Sendable` store closure can read, standing in for `UserDefaults`.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
