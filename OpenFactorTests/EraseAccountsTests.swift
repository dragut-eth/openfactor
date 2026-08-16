import Foundation
import Security
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// Erase has to leave nothing behind, and "nothing" includes the records this version
/// cannot read.
///
/// The interesting case is not the happy one. It is an erase that reports success and
/// leaves a secret on the device, which is the worst outcome available here: the user
/// believes their phone is clean, sells it, and it is not. So the assertion is against the
/// raw Keychain rather than against `records()`, which by definition only sees what it
/// understands.
@Suite("Erase all accounts")
struct EraseAccountsTests {

    private func makeStore() throws -> KeychainSecretStore {
        try UnlockedVault.store()
    }

    private func account(_ issuer: String) -> OTPAccount {
        OTPAccount(
            issuer: issuer,
            name: "octocat",
            secret: Data("12345678901234567890".utf8),
            generator: .totp(.standard)
        )
    }

    /// Counts what is actually in the Keychain for this service, bypassing the store, so a
    /// record the store cannot decode is still counted.
    private func rawItemCount(service: String) -> Int {
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

        guard status == errSecSuccess else { return 0 }
        return (result as? [[String: Any]])?.count ?? 0
    }

    /// Writes an item whose metadata this version cannot decode, which is what a record
    /// written by a newer version looks like to an older one.
    private func addUndecodableItem(service: String) {
        SecItemAdd(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: UUID().uuidString,
                kSecAttrGeneric as String: Data("not json at all".utf8),
                kSecValueData as String: Data("12345678901234567890".utf8),
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary,
            nil
        )
    }

    /// The erase itself, as the view performs it: every readable id and every unreadable
    /// one. Kept in step with `EraseAccountsView.erase()` by being the same two lines.
    private func eraseEverything(in store: KeychainSecretStore) throws {
        let records = try store.records()
        for id in records.readable.map(\.id) + records.unreadable {
            try store.delete(id: id)
        }
    }

    @Test("Erasing removes every account")
    func erasesEverything() throws {
        let store = try makeStore()
        defer { store.cleanUp() }

        for issuer in ["GitHub", "Fastmail", "Proton"] {
            try store.add(account(issuer), color: .blue)
        }
        #expect(rawItemCount(service: store.service) == 3)

        try eraseEverything(in: store)

        #expect(try store.records().readable.isEmpty)
        #expect(rawItemCount(service: store.service) == 0)
    }

    /// The one that matters. A record this version cannot decode is invisible to
    /// `records().readable`, so an erase written against that list alone would leave a
    /// secret on a device its owner believes is empty.
    @Test("Erasing removes records this version cannot decode")
    func erasesUndecodableRecords() throws {
        let store = try makeStore()
        defer { store.cleanUp() }

        try store.add(account("GitHub"), color: .blue)
        addUndecodableItem(service: store.service)

        let before = try store.records()
        #expect(before.readable.count == 1)
        #expect(before.unreadable.count == 1, "the fixture must actually be undecodable")
        #expect(rawItemCount(service: store.service) == 2)

        try eraseEverything(in: store)

        #expect(rawItemCount(service: store.service) == 0, "a secret was left on the device")
    }

    @Test("Erasing an empty store is not an error")
    func erasingNothing() throws {
        let store = try makeStore()
        defer { store.cleanUp() }

        try eraseEverything(in: store)
        #expect(rawItemCount(service: store.service) == 0)
    }

    /// Erase must not reach past its own service into another app's items, or another
    /// store's. The service is the boundary and this is the test that keeps it one.
    @Test("Erasing one store leaves another alone")
    func doesNotReachOtherStores() throws {
        let erased = try makeStore()
        let untouched = try makeStore()
        defer { erased.cleanUp(); untouched.cleanUp() }

        try erased.add(account("GitHub"), color: .blue)
        try untouched.add(account("Fastmail"), color: .green)

        try eraseEverything(in: erased)

        #expect(rawItemCount(service: erased.service) == 0)
        #expect(rawItemCount(service: untouched.service) == 1)
    }
}
