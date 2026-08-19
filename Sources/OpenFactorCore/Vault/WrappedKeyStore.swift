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

    /// Whether a record is there, treating a store that cannot be read as empty.
    ///
    /// **Which is the collapse gate A4 filed, so nothing that matters may use this.** `Vault`
    /// used to, and a transient read failure therefore looked like a fresh device, whose offered
    /// remedy is to create a vault over whatever is really there. `Vault.state()` calls `load()`
    /// and reports `unavailable` now. This is kept for callers with nothing to lose by guessing,
    /// and a caller that has something to lose should call `load()` and handle the throw.
    public var exists: Bool {
        (try? load()) != nil
    }

    // MARK: - Writing

    /// Stores the record, replacing any earlier one.
    ///
    /// **This is the one item in the design that is written more than once**, on a passphrase
    /// change.
    ///
    /// ## Why this looks before it adds
    ///
    /// `kSecAttrSynchronizable` is part of a Keychain item's primary key. An `SecItemAdd` whose
    /// sync flag differs from the existing record's therefore does not collide: it succeeds, and
    /// leaves **two** records under one account identifier. `load` asks with
    /// `kSecAttrSynchronizableAny` and `kSecMatchLimitOne`, so which of the twins a later unlock
    /// reads is unspecified, and a correct passphrase can fail against the wrong one.
    ///
    /// The A4 review found this, and found that it could not fire only because the wrapped key's
    /// flag was permanently `false`: nothing ever made this record synchronizable, which was the
    /// separate and more serious defect fixed alongside it. Making the record follow the sync
    /// preference is exactly what creates the differing flag, so the two had to land together.
    ///
    /// Looking first also stops a passphrase change from silently relocating the record. The old
    /// `SecItemUpdate` put `kSecAttrSynchronizable` in its change dictionary, so changing a
    /// passphrase on a device whose preference had drifted would move the only recovery record
    /// between iCloud and this device as a side effect. **Where the record lives is
    /// `setSynchronizable`'s decision and nothing else's.**
    public func save(_ record: Data) throws(SecretStoreError) {
        // Any, so an existing record is found whichever flag it carries.
        var find = query()
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        find[kSecReturnAttributes as String] = true

        var existing: CFTypeRef?
        let found = SecItemCopyMatching(find as CFDictionary, &existing)

        if found == errSecSuccess {
            // Matched on its own flag, so the update cannot create a twin, and the flag is
            // absent from the changes, so the record does not move.
            var target = query()
            let attributes = existing as? [String: Any]
            target[kSecAttrSynchronizable as String] =
                (attributes?[kSecAttrSynchronizable as String] as? Bool) ?? kSecAttrSynchronizableAny

            // **Only the value changes.** The accessibility used to be written here too, from
            // this store's construction-time default, which is `whenUnlockedThisDeviceOnly`. A
            // record that `setSynchronizable(true)` had moved to iCloud, and to `whenUnlocked`
            // because a synchronizable item cannot be device-only, would be updated back to a
            // device-only class while still flagged as syncing. That is either an error from
            // securityd or a record silently withheld from iCloud, and the second is the exact
            // loss this store exists to prevent. Found in round two of gate A4, filed as
            // plausible rather than confirmed because it needs a device to settle.
            //
            // Where the record lives is `setSynchronizable`'s decision, and the protection class
            // is half of that decision: it writes both together, so nothing else writes either.
            let changes: [String: Any] = [kSecValueData as String: record]
            let updated = SecItemUpdate(target as CFDictionary, changes as CFDictionary)
            guard updated == errSecSuccess else { throw error(for: updated) }
            return
        }

        guard found == errSecItemNotFound else { throw error(for: found) }

        var attributes = query()
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrAccessible as String] = accessibility.attribute
        attributes[kSecAttrLabel as String] = "OpenFactor"
        attributes[kSecValueData as String] = record

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw error(for: status) }
    }

    /// Stores the record only if the store is empty. See `WrappedRecordStore.addIfAbsent`.
    ///
    /// **Two things can be there, and only one of them is a duplicate.** `SecItemAdd` refuses an
    /// item whose primary key already exists, and `kSecAttrSynchronizable` is part of that key,
    /// so a record carrying the opposite flag is not a duplicate to the Keychain: the add
    /// succeeds and leaves a twin. So the add is followed by a count under `Any`, and a twin
    /// found there is undone by removing the record this call just wrote.
    ///
    /// That is a narrowing rather than an elimination, and it is worth saying which. The window
    /// it leaves is between the add and the count, measured in microseconds and needing an
    /// arrival inside it. The window it closes is the one that spanned a 600,000-iteration key
    /// derivation.
    public func addIfAbsent(_ record: Data) throws(SecretStoreError) -> Bool {
        var attributes = query()
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrAccessible as String] = accessibility.attribute
        attributes[kSecAttrLabel as String] = "OpenFactor"
        attributes[kSecValueData as String] = record

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw error(for: status) }

        guard try countingBothFlags() > 1 else { return true }

        // Something with the other flag was already there, so this call was not a creation after
        // all. Remove what it wrote, pinned to this store's own flag so the record that was
        // already present is never the one deleted.
        var mine = query()
        mine[kSecAttrSynchronizable as String] = synchronizable
        SecItemDelete(mine as CFDictionary)
        return false
    }

    /// How many records exist under this service, counting both sync flags.
    private func countingBothFlags() throws(SecretStoreError) -> Int {
        var find = query()
        find[kSecMatchLimit as String] = kSecMatchLimitAll
        find[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(find as CFDictionary, &result)

        if status == errSecItemNotFound { return 0 }
        guard status == errSecSuccess else { throw error(for: status) }
        return (result as? [[String: Any]])?.count ?? 0
    }

    /// Moves the record between iCloud and this device, following the account items.
    ///
    /// **Nothing did this before, which is the defect that loses every account.** The record was
    /// created with `synchronizable: false` and no code path ever changed it, while
    /// `KeychainSecretStore.setSynchronizable` operated on the accounts service alone. Turning
    /// sync on therefore offered iCloud Keychain the ciphertext and kept the only means of
    /// reading it on one device. Replacing that device found every account present and
    /// unreadable, with the passphrase having nothing to unwrap, which is precisely the recovery
    /// the vault design exists to provide.
    ///
    /// Updated in place, and never by deleting and re-adding: a crash between the two would
    /// destroy the only copy of the record that makes recovery possible.
    ///
    /// - Returns: whether a record existed to convert. `false` is not an error; a device with no
    ///   vault has nothing to move.
    @discardableResult
    public func setSynchronizable(_ shouldSync: Bool) throws(SecretStoreError) -> Bool {
        var find = query()
        find[kSecAttrSynchronizable as String] = !shouldSync

        let changes: [String: Any] = [
            kSecAttrSynchronizable as String: shouldSync,
            // A synchronizable item cannot be device-only by definition, so this follows.
            kSecAttrAccessible as String: shouldSync
                ? SecretAccessibility.whenUnlocked.attribute
                : SecretAccessibility.whenUnlockedThisDeviceOnly.attribute,
        ]

        let status = SecItemUpdate(find as CFDictionary, changes as CFDictionary)

        // Nothing to convert: no vault on this device, or it is already on the right side.
        // Idempotent on purpose, so a partial failure can simply be run again.
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw error(for: status) }
        return true
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
