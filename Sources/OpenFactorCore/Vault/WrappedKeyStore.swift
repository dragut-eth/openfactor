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

    /// Follows the account items. The record is ciphertext, and a device that syncs its accounts
    /// and not the means of reading them would be a device that syncs nothing usable.
    ///
    /// **A question rather than a value, asked at each write.** Held as a `Bool`, this was the
    /// sync preference as it stood when the app launched, while `SyncAwareKeychainStore` re-reads
    /// the preference on every call precisely so there is no cached setting to go stale. Enable
    /// sync, erase, and create a new vault in the same session, and a stored `Bool` writes the
    /// wrap device-only while every new account syncs: the original total-loss shape, for one
    /// session, on a phone lost inside it.
    private let synchronizable: @Sendable () -> Bool

    public let accessGroup: String?

    public init(
        service: String = "app.openfactor.vault.key",
        synchronizable: @escaping @Sendable () -> Bool = { false },
        accessGroup: String? = nil
    ) {
        self.service = service
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
        beforeWrite = nil
    }

    /// Runs between reading the store and writing to it, in `save` and in the class repair.
    ///
    /// **A test seam, internal, and `nil` on every path that ships.** What it exists to express is
    /// what iCloud does: a record arriving, or being replaced, in the gap between deciding what to
    /// write and writing it. That gap is where this store's worst defects have lived, and a
    /// property nothing can express is a property nothing can hold onto. This project has already
    /// paid for that lesson twice, in a vault suite that never ran and in a fake whose `save`
    /// could not represent a twin.
    let beforeWrite: (@Sendable () -> Void)?

    /// The initialiser tests use to reach `beforeWrite`.
    init(
        service: String,
        synchronizable: @escaping @Sendable () -> Bool = { false },
        beforeWrite: @escaping @Sendable () -> Void
    ) {
        self.service = service
        self.synchronizable = synchronizable
        accessGroup = nil
        self.beforeWrite = beforeWrite
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
    /// first launch, and it is also the ordinary state of a second device set up while the record
    /// is still travelling, which this project has measured taking half an hour for a freshly
    /// written item. A replacement phone is the other case and is faster: the record is already
    /// resident in the Apple Account, and E8 measured one readable on first launch.
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
    /// Every record under this service, under either flag. See `WrappedRecordStore.candidates`.
    public func candidates() throws(SecretStoreError) -> [WrappedCandidate] {
        var find = query()
        find[kSecMatchLimit as String] = kSecMatchLimitAll
        find[kSecReturnData as String] = true
        find[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(find as CFDictionary, &result)

        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }

        return items.compactMap { item in
            guard let data = item[kSecValueData as String] as? Data else { return nil }
            let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
            return WrappedCandidate(record: data, isSynchronizable: synchronizable)
        }
    }


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
        // **One read decides both things, because two reads of a store another device writes
        // into can disagree.** This counted the records and then asked separately which one to
        // update. A record arriving between those two questions is invisible to the count and can
        // be what the second question returns, so the write lands on a record nothing counted and
        // nobody examined. If that record is the synchronizable one it is the other live vault's
        // only recovery credential, replaced on every device at once.
        //
        // `candidates()` answers both from a single query: how many there are, and which flag the
        // one to write carries.
        let existing = try candidates()

        // **A twin pair is refused.** With two live vaults' records present and no way to tell
        // which belongs to the accounts here, every alternative writes into a slot nobody
        // examined. `unlock` reads every record and tries each, so nobody is locked out while
        // this refuses.
        guard existing.count <= 1 else { throw .twinnedRecord }

        beforeWrite?()

        if let target = existing.first {
            // **Pinned to the flag that was observed, not to whatever a fresh query returns.**
            // A record arriving after the read lands under the other flag and is therefore not
            // this write's target. If the observed record has since gone, the update finds
            // nothing and fails, which is the honest outcome: what this call meant to replace is
            // not there any more.
            var slot = query()
            slot[kSecAttrSynchronizable as String] = target.isSynchronizable

            // **Only the value changes.** The accessibility used to be written here too, from
            // this store's construction-time default, which was device-only. A record that
            // `setSynchronizable(true)` had moved to iCloud, and to `whenUnlocked` because a
            // synchronizable item cannot be device-only, would be updated back to a device-only
            // class while still flagged as syncing: either an error from securityd or a record
            // silently withheld from iCloud, and the second is the exact loss this store exists
            // to prevent.
            //
            // Where the record lives is `setSynchronizable`'s decision, and the protection class
            // is half of that decision: it writes both together, so nothing else writes either.
            let changes: [String: Any] = [kSecValueData as String: record]
            let updated = SecItemUpdate(slot as CFDictionary, changes as CFDictionary)
            guard updated == errSecSuccess else { throw error(for: updated) }
            return
        }

        let shouldSync = synchronizable()
        var attributes = query()
        attributes[kSecAttrSynchronizable as String] = shouldSync
        attributes[kSecAttrAccessible as String] = SecretAccessibility.forSync(shouldSync).attribute
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
    /// **That is a narrowing rather than an elimination, and the remainder is not small in time.**
    /// This comment used to say the window left over was microseconds, between the add and the
    /// count. Round three of gate A4 took that apart: a record carrying the other flag can arrive
    /// from iCloud minutes or hours after the count has already returned one. Two records then
    /// exist, `load()` matches under `Any` with `kSecMatchLimitOne`, and which one it reads is
    /// unspecified, so a correct passphrase can be tested against the wrong wrap and reported as
    /// wrong.
    ///
    /// What this does close is the window that spanned a 600,000-iteration key derivation, and a
    /// twin that is already present when the add runs. Settling a record that arrives later needs
    /// conflict detection after creation, which this does not have.
    public func addIfAbsent(_ record: Data) throws(SecretStoreError) -> Bool {
        // **Asked once, and every decision in this call is made from that one answer.** Asking
        // again below to build the undo means a preference that moved in between names the other
        // slot, and the undo then deletes the record that was already there rather than the one
        // this call just wrote. That is a flag-keyed deletion of a record nobody examined, which
        // is the shape this store removed from `unlock` and must not keep here.
        let shouldSync = synchronizable()

        var attributes = query()
        attributes[kSecAttrSynchronizable as String] = shouldSync
        attributes[kSecAttrAccessible as String] = SecretAccessibility.forSync(shouldSync).attribute
        attributes[kSecAttrLabel as String] = "OpenFactor"
        attributes[kSecValueData as String] = record

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else { throw error(for: status) }

        guard try countingBothFlags() > 1 else { return true }

        // Something with the other flag was already there, so this call was not a creation after
        // all. Remove what it wrote, pinned to the flag this call actually wrote under so the
        // record that was already present is never the one deleted.
        var mine = query()
        mine[kSecAttrSynchronizable as String] = shouldSync
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

    /// What the wrapped record's own sync flag says, and how many records exist.
    ///
    /// **Nothing in the interface has ever shown this**, which is why two of gate A4's findings
    /// about it could only be argued rather than checked. S1-1 was the wrapped key never
    /// syncing while every account did, and S1-13 is the repair for devices already in that
    /// state failing in silence. Both are questions about one boolean nobody could see.
    ///
    /// - Returns: `nil` when there is no record, otherwise whether it is offered to iCloud, and
    ///   the number of records found under both flags. **A count above one is the twin case**,
    ///   S1-12. `load` still resolves it by picking one unspecified, which is why nothing that
    ///   matters reads through `load` alone; `unlock` reads `candidates()` and tries every one.
    public func syncReport() -> (isSynchronizable: Bool, records: Int, protectionMatchesFlag: Bool)?
    {
        guard let items = try? attributesOfEveryRecord(), let first = items.first else {
            return nil
        }

        let synchronizable = (first[kSecAttrSynchronizable as String] as? Bool) ?? false
        return (synchronizable, items.count, items.allSatisfy(Self.protectionMatchesFlag))
    }

    /// Whether one record's protection class is the one its own sync flag requires.
    ///
    /// **Reported because the flag alone cannot say it.** A record written with the flag set and a
    /// device-only class is flagged for iCloud and kept off it, and every readout that asks only
    /// the flag calls that record synced. Two of this gate's findings were about a boolean nobody
    /// could see; this is the second half of the same boolean.
    private static func protectionMatchesFlag(_ item: [String: Any]) -> Bool {
        let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false
        let stored = item[kSecAttrAccessible as String] as? String
        return stored == (SecretAccessibility.forSync(synchronizable).attribute as String)
    }

    private func attributesOfEveryRecord() throws(SecretStoreError) -> [[String: Any]] {
        var find = query()
        find[kSecMatchLimit as String] = kSecMatchLimitAll
        find[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(find as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw error(for: status)
        }
        return items
    }

    /// Brings a record's protection class back into agreement with its own sync flag.
    ///
    /// **Correcting the write did nothing for what was already written.** A record stored with the
    /// flag set and a device-only class is not in `setSynchronizable`'s query, which looks for the
    /// opposite flag, so the reconcile that runs on every foreground passes over it forever. The
    /// flag says iCloud, the class says here, and nothing syncs while every account does.
    ///
    /// **This updates one attribute and nothing else.** It never deletes, never writes the wrap,
    /// and never moves a record between flags: the flag is the record's own statement of where it
    /// belongs, and the class is made to agree with it rather than the other way round. So the
    /// worst this can do to a record it should have left alone is set the class it already had.
    ///
    /// Runs on both directions of the toggle and on the reconcile, and touches only records whose
    /// pair actually disagrees, so an ordinary record is not rewritten on every foreground.
    ///
    /// - Returns: how many records were repaired.
    ///
    /// **Correct under twins**, unlike the conversion: each update is pinned to one record's own
    /// flag and changes no primary-key attribute, so it can neither collide nor pick the wrong
    /// record of a pair.
    @discardableResult
    public func repairProtectionClasses() throws(SecretStoreError) -> Int {
        var repaired = 0

        for item in try attributesOfEveryRecord() where !Self.protectionMatchesFlag(item) {
            let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false

            var slot = query()
            slot[kSecAttrSynchronizable as String] = synchronizable

            let changes: [String: Any] = [
                kSecAttrAccessible as String: SecretAccessibility.forSync(synchronizable).attribute
            ]

            beforeWrite?()

            // **A repair that did not happen must not read as one that did.** Counting a failure
            // as "nothing to repair" let `setSynchronizable` return normally, and its caller
            // converts every account to iCloud on the strength of that return and then commits the
            // preference. The result is accounts in iCloud, the wrapped key device-only, and a
            // switch reading on, which is the loss this repair exists to prevent.
            //
            // The rule is this project's own, from gate A2: the failure that understates exposure
            // must not be the quiet one. `SharedInbox.write` refuses when it cannot exclude a
            // directory from backup and `VaultKeyStore` refuses to write a key it cannot exclude,
            // for the same reason.
            let status = SecItemUpdate(slot as CFDictionary, changes as CFDictionary)
            guard status == errSecSuccess else { throw error(for: status) }
            repaired += 1
        }

        return repaired
    }

    /// Whether a conversion could proceed, without changing anything.
    ///
    /// **For a caller that must not begin work it may have to abandon.** Turning sync off converts
    /// every account before it touches this record, so learning here that the record cannot move
    /// would leave the accounts converted and the preference still claiming otherwise. This is one
    /// read and it refuses for the same reason `setSynchronizable` does.
    public func precheckConversion() throws(SecretStoreError) {
        guard try countingBothFlags() <= 1 else { throw .twinnedRecord }
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
        // **Repaired first, because the repair is correct under twins even though the move is
        // not.** It works one record at a time, pinned to that record's own flag, so a stranded
        // record in a pair is corrected whether or not the conversion below can proceed. Putting
        // the refusal above this would leave such a record wrong on every call that refuses,
        // which is every call, forever.
        try repairProtectionClasses()

        // **A conversion that cannot succeed says so.** Moving the record on this side to the
        // other flag collides with the record already there, and `SecItemUpdate` reports
        // `errSecDuplicateItem`, which reaches a person as advice to try again. It fails the same
        // way every time. `twinnedRecord` is the honest answer and it already existed; nothing
        // threw it here.
        guard try countingBothFlags() <= 1 else { throw .twinnedRecord }

        var find = query()
        find[kSecAttrSynchronizable as String] = !shouldSync

        let changes: [String: Any] = [
            kSecAttrSynchronizable as String: shouldSync,
            // A synchronizable item cannot be device-only by definition, so this follows. The
            // pairing lives in one place now; this was the only site that had it right.
            kSecAttrAccessible as String: SecretAccessibility.forSync(shouldSync).attribute,
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
