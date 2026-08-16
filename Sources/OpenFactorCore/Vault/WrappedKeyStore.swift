import CryptoKit
import Foundation
import Security

/// Where the wrapped vault key lives: one Keychain item, alongside the accounts.
///
/// It is ciphertext, so it syncs like everything else and is useless to anyone holding it
/// without the passphrase. It exists so that a device with no key can recover one, which is the
/// whole of the passphrase path.
///
/// **The presence of this item is what tells a device which question to ask.** No key and no
/// wrapped record is a vault that has never existed, so the app creates one and shows a
/// passphrase. No key and a wrapped record present is a device that has ciphertext and needs the
/// passphrase it was already given. Those are different screens and confusing them is how an app
/// asks somebody to type a passphrase that was never issued.
public struct WrappedKeyStore: Sendable {

    /// Its own service, so a query for accounts never returns it and a query for it never
    /// returns an account.
    public let service: String

    public let accessibility: SecretAccessibility

    /// Follows the account items. The record is ciphertext, and a device that syncs its accounts
    /// and not the means of reading them would be a device that syncs nothing usable.
    public let synchronizable: Bool

    public let accessGroup: String?

    public init(
        service: String = "app.openfactor.vault.key",
        accessibility: SecretAccessibility = .whenUnlockedThisDeviceOnly,
        synchronizable: Bool = false,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessibility = accessibility
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
    }

    private static let account = "wrapped"

    private func query() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
            // Any, so a record written under either sync setting is found. A device that has
            // just turned sync off must still be able to read the record it already had.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    // MARK: - Reading

    /// The record, or `nil` when no vault has ever been created on this Apple Account.
    ///
    /// **`nil` is not an error and must never be shown as one.** It is the ordinary state of a
    /// first launch, and it is also the ordinary state of a device whose record has not finished
    /// arriving, which this project has measured taking half an hour.
    public func load() throws(SecretStoreError) -> Data? {
        var find = query()
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        find[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(find as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw error(for: status)
        }
        return data
    }

    public var exists: Bool {
        (try? load()) != nil
    }

    // MARK: - Writing

    /// Stores the record, replacing any earlier one.
    ///
    /// **This is the one item in the design that is written more than once**, on a passphrase
    /// change. Replacing rather than adding matters: two records under one account identifier is
    /// the twin case gate A2 flagged and this project has never been able to test.
    public func save(_ record: Data) throws(SecretStoreError) {
        var attributes = query()
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrAccessible as String] = accessibility.attribute
        attributes[kSecAttrLabel as String] = "OpenFactor"
        attributes[kSecValueData as String] = record

        let status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let changes: [String: Any] = [
                kSecValueData as String: record,
                kSecAttrSynchronizable as String: synchronizable,
                kSecAttrAccessible as String: accessibility.attribute,
            ]
            let updated = SecItemUpdate(query() as CFDictionary, changes as CFDictionary)
            guard updated == errSecSuccess else { throw error(for: updated) }
            return
        }

        guard status == errSecSuccess else { throw error(for: status) }
    }

    /// Removes it. Used by erase, and never as a way to lock a device: deleting this while
    /// accounts remain would leave ciphertext nobody can ever recover.
    public func delete() throws(SecretStoreError) {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw error(for: status)
        }
    }

    private func error(for status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecItemNotFound: .notFound
        case errSecDuplicateItem: .duplicate
        case errSecInteractionNotAllowed: .deviceLocked
        default: .keychain(status: status)
        }
    }
}
