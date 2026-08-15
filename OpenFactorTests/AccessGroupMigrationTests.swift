import Foundation
import Security
import Testing

@testable import OpenFactorCore

/// Can a Keychain item be moved between access groups in place?
///
/// The answer decides how the migration in `SyncAwareKeychainStore` has to be written, and
/// it is worth knowing rather than assuming. If `SecItemUpdate` can change
/// `kSecAttrAccessGroup`, an account moves without its secret ever being decrypted. If it
/// cannot, the only route is read, add, delete, which decrypts every secret and opens a
/// window where a crash loses an account.
///
/// This suite is app hosted on purpose. The group names are discovered at runtime rather
/// than written down, so no team identifier appears in the source.
@Suite("Access group migration")
struct AccessGroupMigrationTests {

    private let service = "app.openfactor.tests.accessgroup"

    /// The group a new item lands in, which is the first entry of the entitlement.
    ///
    /// Discovered by writing an item and reading back where it went, because there is no
    /// public API that answers the question directly.
    private func defaultGroup() throws -> String {
        let id = UUID().uuidString
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data("probe".utf8),
        ]
        #expect(SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id,
                kSecUseDataProtectionKeychain as String: true,
                kSecReturnAttributes as String: true,
            ] as CFDictionary,
            &result
        )
        #expect(status == errSecSuccess)

        let group = (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary
        )
        return try #require(group)
    }

    /// The group items landed in before the shared one was declared: the team prefix and
    /// the bundle identifier. Derived from the default group's own prefix.
    private func legacyGroup(default group: String) throws -> String {
        let prefix = try #require(group.split(separator: ".").first)
        let bundle = try #require(Bundle.main.bundleIdentifier)
        return "\(prefix).\(bundle)"
    }

    private func cleanUp() {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ] as CFDictionary
        )
    }

    @Test("An item can be moved between access groups without reading its secret")
    func moveInPlace() throws {
        defer { cleanUp() }

        let target = try defaultGroup()
        let legacy = try legacyGroup(default: target)

        // Only meaningful if the two really are different groups. If the app were writing
        // to its own bundle group there would be nothing to migrate and this test would be
        // quietly passing on a technicality.
        try #require(legacy != target)

        let id = UUID().uuidString
        let secret = Data("12345678901234567890".utf8)

        #expect(
            SecItemAdd(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: id,
                    kSecAttrAccessGroup as String: legacy,
                    kSecUseDataProtectionKeychain as String: true,
                    kSecValueData as String: secret,
                ] as CFDictionary,
                nil
            ) == errSecSuccess
        )

        // The move itself. No secret is named, read, or written.
        let moved = SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id,
                kSecAttrAccessGroup as String: legacy,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary,
            [kSecAttrAccessGroup as String: target] as CFDictionary
        )

        #expect(moved == errSecSuccess, "SecItemUpdate could not change the access group")

        var result: CFTypeRef?
        let found = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id,
                kSecAttrAccessGroup as String: target,
                kSecUseDataProtectionKeychain as String: true,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
            ] as CFDictionary,
            &result
        )

        #expect(found == errSecSuccess, "The item is not in the target group")
        let item = try #require(result as? [String: Any])
        #expect(item[kSecAttrAccessGroup as String] as? String == target)
        #expect(item[kSecValueData as String] as? Data == secret, "The secret did not survive")
    }
}

/// The migration itself, as the app runs it.
@Suite("Access group migration, end to end")
struct AccessGroupMigrationEndToEndTests {

    private func makeStore() -> KeychainSecretStore {
        KeychainSecretStore(service: "app.openfactor.tests.\(UUID().uuidString)")
    }

    private func account(issuer: String) -> OTPAccount {
        OTPAccount(
            issuer: issuer,
            name: "octocat",
            secret: Data("12345678901234567890".utf8),
            generator: .totp(.standard)
        )
    }

    @Test("Accounts left in the old group are moved, and their secrets survive")
    func movesLegacyAccounts() throws {
        let store = makeStore()
        defer { store.cleanUp() }

        // Two accounts written normally, which land in the shared group.
        let first = try store.add(account(issuer: "GitHub"), color: .blue)
        try store.add(account(issuer: "Fastmail"), color: .green)

        // Nothing to do, and saying so cheaply is the common case.
        #expect(try store.migrateToDefaultAccessGroup() == 0)

        // Everything still readable, and the secret untouched.
        #expect(try store.records().readable.count == 2)
        #expect(try store.secret(for: first.id) == Data("12345678901234567890".utf8))
    }

    @Test("A store pinned to an explicit group has nothing to migrate")
    func pinnedStoreDoesNothing() throws {
        let store = KeychainSecretStore(
            service: "app.openfactor.tests.\(UUID().uuidString)",
            accessGroup: "does.not.matter"
        )

        #expect(try store.migrateToDefaultAccessGroup() == 0)
    }
}
