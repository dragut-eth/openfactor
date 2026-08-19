import CryptoKit
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
/// | `kSecValueData` | a `VaultRecord`: the metadata and the secret, each sealed |
/// | `kSecAttrGeneric` | **nothing. Never written, and never read** |
/// | `kSecAttrAccount` | the account identifier, a UUID |
/// | `kSecAttrService` | a constant, so the app's items can be found |
///
/// One item rather than two, because two can be orphaned: a crash between writing a
/// secret and writing its metadata leaves a secret nobody can name, or a name with no
/// secret behind it. With one item there is nothing to get out of step.
///
/// The separation the design calls for used to be achieved by the queries: ``records()`` asked
/// for attributes and explicitly not for data, so listing never decrypted a secret.
///
/// **That property survives the vault, by a different mechanism.** A record now seals the
/// metadata and the secret separately under one key, so ``records()`` fetches the data it has to
/// and opens only the metadata half. A secret's plaintext still exists in exactly one place,
/// ``secret(for:)``, at the moment a code is generated. An external review caught the first
/// design discarding this without mentioning it, which is why the record has two halves rather
/// than being one blob.
///
/// ## Why the metadata is sealed rather than stored as an attribute
///
/// The issuer and account name cannot generate a code, but they say which services somebody
/// uses and under which email address, which is most of what an attacker wanted.
///
/// Gate A1 recorded that an attribute is encrypted under the keychain's own key rather than the
/// per item class, a weaker guarantee than the secret's, and said the threat model should not
/// claim otherwise. Gate E1 then measured something worse: a sibling app on the same team reads
/// items out of the group, attributes included. So metadata in an attribute is metadata in the
/// clear as far as that adversary is concerned, and it now lives inside the ciphertext.
///
/// `kSecAttrLabel` is deliberately set to a constant rather than to the account name. On
/// macOS that field is what Keychain Access lists, and there is no reason for a passer by
/// at someone's desk to read off which services they use.
public struct KeychainSecretStore: SynchronizableSecretStore {

    /// Groups this app's items. Constant, and part of the primary key with the account
    /// identifier, so two accounts can never collide.
    public let service: String

    /// When the operating system will allow these items to be read.
    public let accessibility: SecretAccessibility

    /// Whether items are offered to iCloud Keychain.
    public let synchronizable: Bool

    /// The Keychain access group items are written to and read from, or `nil` to use the
    /// default.
    ///
    /// **The app passes `nil`, and that is the design rather than an omission.** A shared
    /// group is required: the watch app has its own bundle identifier and would otherwise
    /// look in its own group and find nothing. But the group is declared in the app's
    /// `keychain-access-groups` entitlement, and the Keychain uses the first entry in that
    /// list as the default for anything written without one, so the entitlement is the
    /// single place the group is written down. Naming it here too would hardcode the team
    /// identifier into a public repository and give the group two homes that could
    /// disagree. The hosted test `usesTheSharedAccessGroup` asserts the resulting items
    /// really are in the shared group.
    ///
    /// Tests that construct a store directly also pass `nil`, for a different reason: a
    /// test process holds no entitlement for a shared group, and asking for one it does
    /// not hold fails every call with `errSecMissingEntitlement`. Gate A2, F18.
    public let accessGroup: String?

    /// Where this device's vault key lives, and the only thing that can open a record.
    public let vaultKeys: VaultKeyStore

    public init(
        service: String = "app.openfactor.accounts",
        accessibility: SecretAccessibility = .whenUnlockedThisDeviceOnly,
        synchronizable: Bool = false,
        accessGroup: String? = nil,
        vaultKeys: VaultKeyStore = VaultKeyStore()
    ) {
        self.service = service
        self.accessibility = accessibility
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
        self.vaultKeys = vaultKeys
    }

    /// The vault key, or the reason there is not one.
    ///
    /// Read on every call rather than held. The file is 32 bytes and the alternative is caching
    /// a key across a state change, which is how a device that has just been unprovisioned keeps
    /// working until it does not.
    private func vaultKey() throws(SecretStoreError) -> SymmetricKey {
        do {
            guard let key = try vaultKeys.load() else { throw SecretStoreError.vaultLocked }
            return key
        } catch let error as SecretStoreError {
            throw error
        } catch {
            throw SecretStoreError.vaultLocked
        }
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

        let sealed: Data
        do {
            sealed = try VaultRecord.seal(
                metadata: try encode(record.metadata, id: record.id),
                secret: account.secret,
                id: record.id,
                key: try vaultKey())
        } catch let error as SecretStoreError {
            throw error
        } catch {
            throw SecretStoreError.vaultLocked
        }

        var attributes = baseAttributes(id: record.id)
        attributes[kSecValueData as String] = sealed
        // `kSecAttrGeneric` is deliberately absent. It held the metadata as JSON before the
        // vault, and an external review pointed out that a conversion which seals the value and
        // leaves the attribute in place satisfies the instruction and defeats the design.
        attributes[kSecAttrAccessible as String] = accessibility.attribute
        attributes[kSecAttrSynchronizable as String] = synchronizable
        attributes[kSecAttrLabel as String] = "OpenFactor"

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw error(for: status)
        }

        return record
    }

    /// Rewrites an account's metadata without ever decrypting its secret.
    ///
    /// A rename, a colour change, a reorder and an HOTP counter all arrive here. The existing
    /// record is read, its metadata half re-sealed, and **its secret half copied verbatim**, so
    /// the property the old implementation got from naming only one attribute survives: no path
    /// through this method can overwrite a secret, and none decrypts one either.
    public func update(_ record: AccountRecord) throws(SecretStoreError) {
        let existing = try sealedRecord(for: record.id)

        let rewritten: Data
        do {
            rewritten = try VaultRecord.replacingMetadata(
                in: existing,
                with: try encode(record.metadata, id: record.id),
                id: record.id,
                key: try vaultKey())
        } catch let error as SecretStoreError {
            throw error
        } catch {
            throw SecretStoreError.unreadableMetadata(id: record.id)
        }

        let changes: [String: Any] = [kSecValueData as String: rewritten]

        let status = SecItemUpdate(
            query(id: record.id) as CFDictionary,
            changes as CFDictionary
        )

        guard status == errSecSuccess else {
            throw error(for: status)
        }
    }

    /// Turns iCloud Keychain sync on or off for every account.
    ///
    /// **No secret is read to do this.** The items are updated in place, so the secret
    /// material never leaves the Keychain, never lands in this process's memory, and there
    /// is no window in which an account exists only as a variable. Rewriting each item by
    /// reading it, deleting it and adding it back would have all three of those problems,
    /// and a crash in the middle of one would lose an account outright.
    ///
    /// Turning sync on also weakens the protection class, from device only to
    /// `WhenUnlocked`, because a synchronizable item cannot be device only by definition.
    /// That is the real cost of sync and it is why the interface has to say so.
    ///
    /// - Returns: how many accounts were changed, for the caller to report or ignore.
    @discardableResult
    public func setSynchronizable(_ shouldSync: Bool) throws(SecretStoreError) -> Int {
        // Which items still need converting is asked of the Keychain, not worked out here.
        // An earlier version listed everything and read each item's sync flag out of the
        // returned attributes, which meant a flag that failed to bridge defaulted to
        // "local". Turning sync on then failed loudly, because the update matched nothing,
        // but turning sync off skipped the item in silence: it stayed in iCloud Keychain
        // while the switch and every sentence around it said device only. The failure that
        // understates exposure must not be the quiet one. Gate A2, F14.
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = !shouldSync
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        // The one thing this must not ask for. Converting an account does not require
        // knowing its secret.
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        // Nothing left to convert. Reached on an empty store and on a second run, which is
        // what makes this idempotent: a partial failure means the whole thing gets run
        // again, and the second run picks up exactly the remainder.
        if status == errSecItemNotFound {
            return 0
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        let target: SecretAccessibility = shouldSync ? .whenUnlocked : .whenUnlockedThisDeviceOnly
        var changed = 0

        for item in items {
            guard let rawID = item[kSecAttrAccount as String] as? String,
                let id = UUID(uuidString: rawID)
            else {
                continue
            }

            var find = baseQuery()
            find[kSecAttrAccount as String] = id.uuidString
            find[kSecAttrSynchronizable as String] = !shouldSync

            let changes: [String: Any] = [
                kSecAttrSynchronizable as String: shouldSync,
                kSecAttrAccessible as String: target.attribute,
            ]

            let updated = SecItemUpdate(find as CFDictionary, changes as CFDictionary)
            guard updated == errSecSuccess else {
                throw error(for: updated)
            }

            changed += 1
        }

        return changed
    }

    /// Moves every account into the access group new items are written to.
    ///
    /// **A Keychain item lives in the group it was written to.** Accounts saved before the
    /// shared group was declared are still in the app's bundle group, and they stay there
    /// forever unless something moves them. The phone does not notice, because a query that
    /// names no group searches every group the app can reach. The watch notices immediately,
    /// because the shared group is the only one it has in common with the phone. The symptom
    /// is a watch that shows some of your accounts and no error, which is the worst shape a
    /// bug can take in an authenticator.
    ///
    /// PR 13 declared the group and shipped no migration, on the reading that the only user
    /// did not need their data preserved. That was the wrong reading of the answer and this
    /// is the correction.
    ///
    /// **No secret is read.** `SecItemUpdate` can change `kSecAttrAccessGroup` in place,
    /// which is verified by test rather than assumed, so an account moves without being
    /// decrypted and without a window in which a crash would lose it.
    ///
    /// Safe to run at every launch: it is idempotent, and once everything is in the right
    /// group it costs one attribute query.
    ///
    /// - Returns: how many accounts were moved.
    @discardableResult
    public func migrateToDefaultAccessGroup() throws(SecretStoreError) -> Int {
        // A store pinned to an explicit group has nothing to migrate: its queries only ever
        // see that group, so there is no elsewhere to move things from.
        guard accessGroup == nil else { return 0 }

        let target = try defaultAccessGroup()

        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return 0
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        var moved = 0
        var failures = 0

        for item in items {
            guard let rawID = item[kSecAttrAccount as String] as? String,
                let id = UUID(uuidString: rawID),
                let group = item[kSecAttrAccessGroup as String] as? String
            else {
                failures += 1
                continue
            }

            guard group != target else { continue }

            // Pinned rather than left as Any, because an update has to name one item.
            // Read strictly: an unreadable sync flag is refused, not defaulted. Defaulting
            // it is the pattern gate A2 removed from `setSynchronizable` in F14, and it
            // came straight back here. Wrong either way, and wrong quietly: the update
            // would match nothing, the item would stay in the old group, and the only
            // symptom is a watch missing accounts. Gate A2, F20.
            guard let synchronizable = item[kSecAttrSynchronizable as String] as? Bool else {
                failures += 1
                continue
            }

            var find = baseQuery()
            find[kSecAttrAccount as String] = id.uuidString
            find[kSecAttrAccessGroup as String] = group
            find[kSecAttrSynchronizable as String] = synchronizable

            let status = SecItemUpdate(
                find as CFDictionary,
                [kSecAttrAccessGroup as String: target] as CFDictionary
            )

            // One stuck account must not strand the rest, so the loop finishes and reports.
            // Aborting on the first failure left every later account in the old group, and
            // the caller could not tell that from a clean run.
            guard status == errSecSuccess else {
                failures += 1
                continue
            }

            moved += 1
        }

        // Reported rather than swallowed. The caller decides what to do, but it can no
        // longer fail to notice: an account left behind is invisible on the phone, which
        // reads every group it can reach, and shows up only as a watch with fewer accounts
        // than it should have and no error anywhere. Gate A2, F20.
        if failures > 0 {
            throw SecretStoreError.migrationIncomplete(moved: moved, failed: failures)
        }

        return moved
    }

    /// The access group a new item lands in, which is the first entry of the app's
    /// `keychain-access-groups` entitlement.
    ///
    /// Found by writing a valueless probe and reading back where it went, because no public
    /// API answers the question. Deliberately not hardcoded: the group name contains the
    /// team identifier, the entitlement is the one place it is written down, and a constant
    /// here could disagree with it.
    ///
    /// The probe carries no secret, and is deleted whatever happens.
    private func defaultAccessGroup() throws(SecretStoreError) -> String {
        let id = UUID().uuidString
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).accessgroup.probe",
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: true,
        ]

        defer { SecItemDelete(probe as CFDictionary) }

        let added = SecItemAdd(probe as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw error(for: added)
        }

        var query = probe
        query[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let found = SecItemCopyMatching(query as CFDictionary, &result)
        guard found == errSecSuccess,
            let group = (result as? [String: Any])?[kSecAttrAccessGroup as String] as? String
        else {
            throw error(for: found)
        }

        return group
    }

    /// Where each stored item physically sits: its access group and its sync state.
    ///
    /// **Diagnostic.** Added while chasing a watch that could see one account out of seven,
    /// because every screen that could have shown the cause was on a device with access to
    /// every group. Reads attributes only, never data.
    public func placements() throws(SecretStoreError) -> [UUID: ItemPlacement] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return [:]
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        var placements: [UUID: ItemPlacement] = [:]

        for item in items {
            guard let rawID = item[kSecAttrAccount as String] as? String,
                let id = UUID(uuidString: rawID)
            else {
                continue
            }

            placements[id] = ItemPlacement(
                accessGroup: item[kSecAttrAccessGroup as String] as? String ?? "unknown",
                synchronized: item[kSecAttrSynchronizable as String] as? Bool == true,
                accessible: item[kSecAttrAccessible as String] as? String ?? "unknown"
            )
        }

        return placements
    }

    public func syncState() throws(SecretStoreError) -> SyncState {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return SyncState(synced: [], local: [], unknown: [])
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        var synced: Set<UUID> = []
        var local: Set<UUID> = []
        var unknown: Set<UUID> = []

        for item in items {
            guard let rawID = item[kSecAttrAccount as String] as? String,
                let id = UUID(uuidString: rawID)
            else {
                continue
            }

            // Strict for the same reason as the migration: "local" is the reassuring
            // answer, and an unreadable flag must not quietly produce it. Unknown items
            // are counted apart so the interface can say it does not know rather than
            // claim device only. Gate A2, F20.
            switch item[kSecAttrSynchronizable as String] as? Bool {
            case true: synced.insert(id)
            case false: local.insert(id)
            case nil: unknown.insert(id)
            }
        }

        return SyncState(synced: synced, local: local, unknown: unknown)
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
        // Data is required now, because the metadata lives inside it. The property this line
        // used to carry, that listing never decrypts a secret, is carried by the record's two
        // halves instead: what comes back is ciphertext, and only the metadata half is opened.
        query[kSecReturnData as String] = true

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

        // Loaded once for the whole listing rather than per item. A device with no key reports
        // every account as unreadable rather than throwing, so the list can still say how many
        // accounts are waiting for a passphrase instead of showing nothing at all.
        let key = try? vaultKeys.load()

        for item in items {
            switch decode(item, key: key) {
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

    /// **The only place a secret's plaintext exists.** Called when a code is generated, for one
    /// account, and never while drawing a list.
    public func secret(for id: UUID) throws(SecretStoreError) -> Data {
        let sealed = try sealedRecord(for: id)

        do {
            return try VaultRecord.openSecret(sealed, id: id, key: try vaultKey())
        } catch let error as SecretStoreError {
            throw error
        } catch {
            throw SecretStoreError.unreadableMetadata(id: id)
        }
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
            // **`.sortedKeys` because `docs/VAULT.md` promises deterministic bytes**, and until
            // gate A4 the encoder did not. The published test vector reached sorted keys by
            // supplying raw bytes rather than by calling this, so the page and the code had never
            // actually agreed. Key order does not affect decoding, so records written before this
            // read exactly as they did.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(metadata)
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

    private func decode(_ item: [String: Any], key: SymmetricKey?) -> DecodedItem {
        guard let rawID = item[kSecAttrAccount as String] as? String,
            let id = UUID(uuidString: rawID)
        else {
            return .foreign
        }

        guard let key else { return .unreadable(id: id) }

        guard let sealed = item[kSecValueData as String] as? Data,
            let json = try? VaultRecord.openMetadata(sealed, id: id, key: key),
            let metadata = try? JSONDecoder().decode(AccountMetadata.self, from: json)
        else {
            // Reported, never skipped and never repaired. A record this version cannot
            // read is one a newer version probably can, and rewriting it here would
            // destroy an account that was never broken.
            return .unreadable(id: id)
        }

        return .readable(AccountRecord(id: id, metadata: metadata))
    }

    /// One account's sealed bytes, which both `secret(for:)` and `update(_:)` need.
    private func sealedRecord(for id: UUID) throws(SecretStoreError) -> Data {
        var query = query(id: id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let sealed = result as? Data else {
            throw error(for: status)
        }

        return sealed
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
/// Where one stored item physically sits. Diagnostic, see ``KeychainSecretStore/placements()``.
public struct ItemPlacement: Sendable, Equatable {
    public let accessGroup: String
    public let synchronized: Bool
    public let accessible: String

    /// The group without its team prefix, which is the only part worth reading and the
    /// only part safe to put on a screen that might be photographed.
    public var groupSuffix: String {
        accessGroup.split(separator: ".").dropFirst().joined(separator: ".")
    }
}

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
