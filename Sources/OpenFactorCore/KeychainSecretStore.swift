import Foundation
import Security

/// The real store. One Keychain item per account.
///
/// ## What is stored where
///
/// Each account is a single generic password item:
///
/// | Keychain field | Holds |
/// | --- | --- |
/// | `kSecValueData` | the secret, and nothing else |
/// | `kSecAttrGeneric` | the metadata, as JSON |
/// | `kSecAttrAccount` | the account identifier, a UUID |
/// | `kSecAttrService` | a constant, so the app's items can be found |
///
/// One item rather than two, because two can be orphaned: a crash between writing a
/// secret and writing its metadata leaves a secret nobody can name, or a name with no
/// secret behind it. With one item there is nothing to get out of step.
///
/// The separation the design calls for is achieved by the queries instead, and more
/// strongly than storing them apart would manage. ``records()`` asks for attributes and
/// explicitly not for data, so listing accounts never decrypts a single secret. Only
/// ``secret(for:)`` asks for data, for one account, at the moment a code is generated.
///
/// ## Why the metadata is in the Keychain too
///
/// The issuer and account name cannot generate a code, but they say which services
/// someone uses and under which email address. Keeping them in a plist or a database file
/// would leave that in the clear on the device and in every unencrypted backup. In the
/// Keychain they are encrypted at rest.
///
/// To be exact about the strength of that, because this project's claims should be no
/// stronger than the facts: the accessibility class chosen below protects the item's
/// **data**, meaning the secret. Attributes, and the metadata JSON lives in one, are
/// encrypted under the keychain's own key rather than the per item class, which is a
/// weaker guarantee than the secret gets. Still encrypted at rest and still absent from
/// unencrypted backups, but not "the same protection as the secret", and the threat
/// model should not claim otherwise. Noted at gate A1.
///
/// `kSecAttrLabel` is deliberately set to a constant rather than to the account name. On
/// macOS that field is what Keychain Access lists, and there is no reason for a passer by
/// at someone's desk to read off which services they use.
public struct KeychainSecretStore: SecretStore {

    /// Groups this app's items. Constant, and part of the primary key with the account
    /// identifier, so two accounts can never collide.
    public let service: String

    /// When the operating system will allow these items to be read.
    public let accessibility: SecretAccessibility

    /// Whether items are offered to iCloud Keychain.
    public let synchronizable: Bool

    /// The Keychain access group items are written to and read from.
    ///
    /// Named explicitly rather than left to the default, which is derived from the bundle
    /// identifier. The watch app has its own bundle identifier and would therefore look in
    /// its own group and find nothing, so both targets declare this one and iCloud
    /// Keychain carries items between them.
    ///
    /// `nil` means the default group, which is what tests use: a test process has no
    /// entitlement for a shared group, and asking for one it does not hold fails every
    /// call with `errSecMissingEntitlement`.
    public let accessGroup: String?

    public init(
        service: String = "app.openfactor.accounts",
        accessibility: SecretAccessibility = .whenUnlockedThisDeviceOnly,
        synchronizable: Bool = false,
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessibility = accessibility
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
    }

    // MARK: - Writing

    @discardableResult
    public func add(
        _ account: OTPAccount,
        color: AccountColor
    ) throws(SecretStoreError) -> AccountRecord {
        let existing = try records().readable
        let record = AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: account.issuer,
                name: account.name,
                generator: account.generator,
                color: color,
                // Appended to the end. Computed here because the store is the only thing
                // that can see the other accounts.
                sortIndex: (existing.map(\.metadata.sortIndex).max() ?? -1) + 1
            )
        )

        var attributes = baseAttributes(id: record.id)
        attributes[kSecValueData as String] = account.secret
        attributes[kSecAttrGeneric as String] = try encode(record.metadata, id: record.id)
        attributes[kSecAttrAccessible as String] = accessibility.attribute
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrLabel as String] = "OpenFactor"

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw error(for: status)
        }

        return record
    }

    public func update(_ record: AccountRecord) throws(SecretStoreError) {
        // Only the metadata is named here, so there is no path through this method that
        // can overwrite a secret.
        let changes: [String: Any] = [
            kSecAttrGeneric as String: try encode(record.metadata, id: record.id)
        ]

        let status = SecItemUpdate(
            query(id: record.id) as CFDictionary,
            changes as CFDictionary
        )

        guard status == errSecSuccess else {
            throw error(for: status)
        }
    }

    public func delete(id: UUID) throws(SecretStoreError) {
        let status = SecItemDelete(query(id: id) as CFDictionary)

        guard status == errSecSuccess else {
            throw error(for: status)
        }
    }

    // MARK: - Reading

    public func records() throws(SecretStoreError) -> StoredRecords {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        // Named explicitly, rather than left to the default, because this is the line
        // that keeps drawing the list from decrypting any secrets.
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return StoredRecords(readable: [])
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        // A plain loop rather than compactMap, because the rethrowing version widens the
        // error type back to `any Error` and loses the typed throws on this method.
        var readable: [AccountRecord] = []
        var unreadable: [UUID] = []

        for item in items {
            switch decode(item) {
            case let .readable(record): readable.append(record)
            case let .unreadable(id): unreadable.append(id)
            case .foreign: continue
            }
        }

        return StoredRecords(
            readable: readable.sorted {
                ($0.metadata.sortIndex, $0.metadata.name) < ($1.metadata.sortIndex, $1.metadata.name)
            },
            unreadable: unreadable
        )
    }

    public func secret(for id: UUID) throws(SecretStoreError) -> Data {
        var query = query(id: id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let secret = result as? Data else {
            throw error(for: status)
        }

        return secret
    }

    // MARK: - Queries

    /// The fields that identify this app's items, shared by every query and write.
    private func baseAttributes(id: UUID) -> [String: Any] {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            // Forces the modern keychain on macOS, where the legacy file based one is
            // still the default and does not honour kSecAttrAccessible.
            kSecUseDataProtectionKeychain as String: true,
        ]

        if let accessGroup {
            attributes[kSecAttrAccessGroup as String] = accessGroup
        }

        return attributes
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
            // Matches both local and synced items. Without this, turning sync on would
            // make every existing account appear to vanish.
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    private func query(id: UUID) -> [String: Any] {
        var query = baseQuery()
        query[kSecAttrAccount as String] = id.uuidString
        return query
    }

    // MARK: - Metadata

    private func encode(_ metadata: AccountMetadata, id: UUID) throws(SecretStoreError) -> Data {
        do {
            return try JSONEncoder().encode(metadata)
        } catch {
            // Only reachable if a future field is not encodable, which is a programming
            // error rather than anything the user did.
            throw SecretStoreError.unreadableMetadata(id: id)
        }
    }

    /// What one Keychain item turned out to be.
    private enum DecodedItem {
        case readable(AccountRecord)
        case unreadable(id: UUID)
        /// Not one of ours, or written by something else under the same service name.
        case foreign
    }

    private func decode(_ item: [String: Any]) -> DecodedItem {
        guard let rawID = item[kSecAttrAccount as String] as? String,
            let id = UUID(uuidString: rawID)
        else {
            return .foreign
        }

        guard let json = item[kSecAttrGeneric as String] as? Data,
            let metadata = try? JSONDecoder().decode(AccountMetadata.self, from: json)
        else {
            // Reported, never skipped and never repaired. A record this version cannot
            // read is one a newer version probably can, and rewriting it here would
            // destroy an account that was never broken.
            return .unreadable(id: id)
        }

        return .readable(AccountRecord(id: id, metadata: metadata))
    }

    // MARK: - Status codes

    private func error(for status: OSStatus) -> SecretStoreError {
        switch status {
        case errSecItemNotFound: .notFound
        case errSecDuplicateItem: .duplicate
        case errSecInteractionNotAllowed: .deviceLocked
        default: .keychain(status: status)
        }
    }
}

/// When the operating system will let an item be read.
///
/// Only the two values this app has a use for, rather than all of them, so that a
/// weaker protection class cannot be selected by accident.
public enum SecretAccessibility: Sendable, Equatable {

    /// Readable only while the device is unlocked, and never restored to another device.
    ///
    /// The default, and the right answer for anything that does not sync. The item is
    /// encrypted with a key derived from the device passcode and the Secure Enclave, so a
    /// locked or wiped device gives up nothing, and it is excluded from encrypted backups
    /// and from migration to a new device.
    case whenUnlockedThisDeviceOnly

    /// Readable only while the device is unlocked, and allowed to leave the device.
    ///
    /// **Required for iCloud Keychain sync,** which cannot carry a device only item, and
    /// is therefore the accessibility PR 13 has to switch to when sync is turned on. It is
    /// a genuine weakening: the item can now be restored to another device the user owns.
    /// That is the whole point of sync, and it is why sync is opt in and explained in
    /// plain words before it is enabled.
    case whenUnlocked

    var attribute: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        }
    }
}
