import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The vault's decisions, checked without a Keychain.
///
/// **`VaultTests` is skipped on the machine this suite runs on.** The test binary is unsigned, so
/// every Keychain write returns `errSecMissingEntitlement`, and the whole `Vault lifecycle` suite
/// is gated on that. It was written to be run on a device and quietly never runs anywhere else,
/// which was discovered while proving gate A4's scope 1 fixes: each fix was reverted in turn and
/// the suite stayed green every time.
///
/// So the decisions that destroy accounts when they are wrong, whether creating would replace an
/// existing record, whether a refused record blames the passphrase, whether a read failure looks
/// like an empty store, are checked here instead, against `InMemoryWrappedStore`. Nothing in this
/// file touches the Keychain, so nothing in it can be skipped.
@Suite("Vault decisions")
struct VaultDecisionTests {

    private func makeVault() -> (Vault, VaultKeyStore, InMemoryWrappedStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-decisions-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        let wrapped = InMemoryWrappedStore()
        return (Vault(keys: keys, wrapped: wrapped), keys, wrapped)
    }

    /// **The destructive tap.** `save` replaces the record it finds, so creating a vault on a
    /// device that already has one strands every stored account under a passphrase nobody was
    /// given. Two reviews found this independently; it is dormant only while the wrapped key
    /// never syncs, and that defect was fixed first, which is what makes this one reachable.
    @Test("Creating refuses when a vault is already there")
    func creatingRefusesAnExistingVault() throws {
        let (vault, keys, wrapped) = makeVault()

        let first = try vault.create()
        let recordBefore = try #require(wrapped.storedRecord)

        #expect(throws: Vault.VaultError.alreadyExists) {
            try vault.create(with: "second passphrase entirely")
        }

        #expect(wrapped.storedRecord == recordBefore, "the record that opens the accounts is intact")
        let key = try #require(try keys.load())
        #expect(
            key.withUnsafeBytes { Data($0) } == first.key.withUnsafeBytes { Data($0) },
            "and so is the key")
    }

    /// The same refusal from the state that matters most: a record has arrived and this device
    /// has no key yet, which is exactly the second phone set up the same day.
    @Test("Creating refuses when a record arrived but no key is here")
    func creatingRefusesAnArrivedRecord() throws {
        let (vault, keys, wrapped) = makeVault()

        _ = try vault.create()
        try keys.discard()
        #expect(vault.state() == .locked)

        #expect(throws: Vault.VaultError.alreadyExists) {
            try vault.create(with: "a passphrase this device made up")
        }
    }

    /// **The race two engines walked out independently, and the reason this fake gained a hook.**
    /// The existence check runs, then 600,000 rounds of PBKDF2, and only then the write. A record
    /// arriving from iCloud inside that window was replaced by a wrap of a brand new vault key,
    /// and every account sealed under the old one became unopenable by anybody.
    @Test("A record arriving during the key derivation is not overwritten")
    func recordArrivingDuringCreationIsNotOverwritten() throws {
        let (vault, keys, wrapped) = makeVault()

        // What iCloud does, at the one moment it does the most damage.
        let arrived = Data("a wrapped key from the phone this replaced".utf8)
        wrapped.duringWrite = { [wrapped] in
            if wrapped.storedRecord == nil { try? wrapped.save(arrived) }
        }

        #expect(throws: Vault.VaultError.alreadyExists) {
            try vault.create(with: "the passphrase this device just generated")
        }

        #expect(wrapped.storedRecord == arrived, "the arrived record is untouched")
        #expect(try keys.load() == nil, "and no key was installed to go with a wrap that is gone")
    }

    /// **The ordering the whole recovery story rests on, which nothing could check until the
    /// fake could fail a write.** The record is written before the key, deliberately: a key with
    /// no record is a device that works until it is replaced and then cannot be recovered by
    /// anybody, while a record with no key is merely a device that must be unlocked. The bad
    /// order fails silently and the safe one fails visibly.
    @Test("A record that cannot be written leaves no key behind")
    func aFailedRecordWriteInstallsNoKey() throws {
        let (vault, keys, wrapped) = makeVault()
        wrapped.writeFailure = .keychain(status: errSecInteractionNotAllowed)

        #expect(throws: (any Error).self) {
            try vault.create(with: "the passphrase this device just generated")
        }

        #expect(try keys.load() == nil, "no key, because nothing could record how to recover it")
        #expect(wrapped.storedRecord == nil)
        #expect(vault.state() == .absent, "so the device offers setup again, which is recoverable")
    }

    /// **A record refused before any derivation ran is not a passphrase problem.** Reporting it
    /// as one sends somebody to retype a passphrase they have written down correctly, against a
    /// record written by a newer version of this app.
    @Test("A record this build cannot read says so rather than blaming the passphrase")
    func unreadableRecordIsNotAWrongPassphrase() throws {
        let (vault, keys, wrapped) = makeVault()

        _ = try vault.create()
        try keys.discard()

        try wrapped.save(Data("not a wrapped key at all, by any version".utf8))

        #expect(throws: Vault.VaultError.recordNotUnderstood) {
            try vault.unlock(with: "whatever was written down")
        }
    }

    /// The same refusal for the other reason it is decided before derivation: an iteration count
    /// this build will not accept. Tested separately because the two arrive by different routes
    /// through the same switch, and a review noticed only one of them had a test.
    @Test("An iteration count out of range is also not a passphrase problem")
    func iterationCountOutOfRangeIsNotAWrongPassphrase() throws {
        let (vault, keys, wrapped) = makeVault()

        _ = try vault.create()
        try keys.discard()

        // A well formed record whose iteration count is rewritten to something absurd. The count
        // is four big-endian bytes at offset 36, after the magic, the salt and nothing else.
        var record = try #require(wrapped.storedRecord)
        record.replaceSubrange(36..<40, with: [0xFF, 0xFF, 0xFF, 0xFF])
        try wrapped.save(record)

        #expect(throws: Vault.VaultError.recordNotUnderstood) {
            try vault.unlock(with: "whatever was written down")
        }
    }

    /// The other side of it: a genuine wrong passphrase must still say so.
    @Test("A wrong passphrase is still a wrong passphrase")
    func wrongPassphraseStillReported() throws {
        let (vault, keys, wrapped) = makeVault()

        _ = try vault.create()
        try keys.discard()

        #expect(throws: Vault.VaultError.wrongPassphrase) {
            try vault.unlock(with: "hedgehog banana turnip windmill lantern")
        }
    }

    /// **Nothing is written before the replacement has been shown.** The one-shot saved first and
    /// returned the string afterwards, so a crash between the two left a vault whose only
    /// recovery credential nobody had ever seen, on a device that kept working and so signalled
    /// nothing at all.
    @Test("Preparing a replacement passphrase writes nothing")
    func preparingAReplacementWritesNothing() throws {
        let (vault, _, wrapped) = makeVault()

        _ = try vault.create()
        let before = try #require(wrapped.storedRecord)

        let replacement = try vault.prepareReplacementPassphrase()
        #expect(!replacement.isEmpty)
        #expect(wrapped.storedRecord == before, "the record is untouched until it is committed")

        try vault.replacePassphrase(with: replacement)
        #expect(wrapped.storedRecord != before, "and changed once it is")

        // And the replacement is the passphrase that now opens it.
        #expect(throws: Never.self) { try vault.unlock(with: replacement) }
    }


    // MARK: - A store that cannot be read

    /// **The collapse that made a read failure look like a fresh device.** `exists` was
    /// `(try? load()) != nil`, so a Keychain error and an empty store gave the same answer, and
    /// the answer's remedy is to create a vault over whatever is really there.
    @Test("A store that cannot be read is not an empty one")
    func unreadableIsNotAbsent() throws {
        let (vault, _, wrapped) = makeVault()

        #expect(vault.state() == .absent)

        wrapped.readFailure = .keychain(status: errSecInteractionNotAllowed)
        #expect(vault.state() == .unavailable, "not absent, which offers to overwrite")
    }

    /// And the state that refuses to guess also refuses to create.
    @Test("Creating refuses while the store cannot be read")
    func creatingRefusesWhileUnreadable() throws {
        let (vault, _, wrapped) = makeVault()
        wrapped.readFailure = .keychain(status: errSecInteractionNotAllowed)

        // Not `(any Error).self`: a review pointed out that would pass if creation refused for
        // any reason at all, including the wrong one.
        #expect(throws: Vault.VaultError.storage(.keychain(status: errSecNotAvailable))) {
            try vault.create(with: "a passphrase somebody just generated")
        }
        #expect(wrapped.storedRecord == nil, "and wrote nothing while it could not see")
    }

    @Test("A device holding a record and no key is locked, not absent")
    func recordWithoutKeyIsLocked() throws {
        let (vault, keys, _) = makeVault()

        _ = try vault.create()
        try keys.discard()

        #expect(vault.state() == .locked)
    }

    // MARK: - S1-12, the twin

    /// **The defect: a correct passphrase reported as wrong.** Two records can exist, because the
    /// sync flag is part of a Keychain item's primary key, so a record arriving from iCloud after
    /// this device wrote its own is a second item rather than a duplicate. Reading one of them and
    /// hoping meant the passphrase could be tried against the wrong wrap and refused.
    @Test("A passphrase opens its own wrap even when a twin is read first")
    func aTwinDoesNotHideTheRightWrap() throws {
        let (vault, keys, wrapped) = makeVault()

        // The wrap that belongs to somebody else's vault, sitting where `load` would find it.
        let stranger = try BackupPassphraseFixture.wrap(passphrase: "a different vault entirely")
        try wrapped.save(stranger)

        // And this device's own, arriving under the other flag.
        let mine = try BackupPassphraseFixture.wrap(passphrase: "the passphrase somebody wrote down")
        wrapped.plantTwin(mine, isSynchronizable: true)
        #expect(wrapped.recordCount == 2, "the premise: two records, one unspecified winner")

        try vault.unlock(with: "the passphrase somebody wrote down")

        #expect(try keys.load() != nil, "the vault opened")
    }

    /// **Both wraps survive a successful unlock, whichever passphrase was typed.** This test
    /// replaces one that asserted the opposite: that the record the passphrase did not open was
    /// discarded, as a wrap "for a vault that no longer exists". All three engines of round four
    /// rejected the premise. Opening a wrap proves which record that passphrase belongs to and
    /// nothing about the other, because nothing in OFK1 binds a wrap to the account ciphertext,
    /// and in the state that produces twins both records are live vaults' only recovery
    /// credentials. The two wraps here are around two fresh random keys, exactly that state.
    ///
    /// Reintroduce a discard into `unlock` and both halves of this go red.
    @Test("A successful unlock deletes nothing, in either direction")
    func aSuccessfulUnlockDeletesNothing() throws {
        let (vault, _, wrapped) = makeVault()

        try wrapped.save(try BackupPassphraseFixture.wrap(passphrase: "phone A's passphrase"))
        wrapped.plantTwin(
            try BackupPassphraseFixture.wrap(passphrase: "phone B's passphrase"),
            isSynchronizable: true)

        try vault.unlock(with: "phone B's passphrase")
        #expect(wrapped.recordCount == 2, "the wrap this passphrase did not open is untouched")

        try vault.unlock(with: "phone A's passphrase")
        #expect(wrapped.recordCount == 2, "and the same is true typed the other way around")
    }

    /// **A replacement cannot pick between twins, so it refuses.** `save` under a one-item match
    /// would update whichever record it found, which with two live vaults present can overwrite
    /// the wrong vault's only recovery credential and propagate the mistake through iCloud. The
    /// same destruction as the discard, through a different door, needing no unlock.
    @Test("A passphrase change is refused while two records exist")
    func replacementRefusesTwins() throws {
        let (vault, _, wrapped) = makeVault()

        try wrapped.save(try BackupPassphraseFixture.wrap(passphrase: "phone A's passphrase"))
        wrapped.plantTwin(
            try BackupPassphraseFixture.wrap(passphrase: "phone B's passphrase"),
            isSynchronizable: true)
        try vault.unlock(with: "phone B's passphrase")

        let replacement = try vault.prepareReplacementPassphrase()
        #expect(throws: Vault.VaultError.storage(.twinnedRecord)) {
            try vault.replacePassphrase(with: replacement)
        }
        #expect(wrapped.recordCount == 2, "and neither record was touched by the refusal")
    }

    /// A genuinely wrong passphrase is still wrong, however many records there are.
    @Test("A wrong passphrase against two records is still a wrong passphrase")
    func wrongPassphraseAgainstTwins() throws {
        let (vault, _, wrapped) = makeVault()

        try wrapped.save(try BackupPassphraseFixture.wrap(passphrase: "one vault"))
        wrapped.plantTwin(
            try BackupPassphraseFixture.wrap(passphrase: "another vault"), isSynchronizable: true)

        #expect(throws: Vault.VaultError.wrongPassphrase) {
            try vault.unlock(with: "neither of them")
        }
        #expect(wrapped.recordCount == 2, "nothing is discarded when nothing opened")
    }

    /// One unreadable record beside a real wrap should report the passphrase, not the rubbish.
    @Test("Rubbish beside a real wrap does not change what the person is told")
    func rubbishBesideARealWrap() throws {
        let (vault, _, wrapped) = makeVault()

        try wrapped.save(Data("not a wrapped key at all".utf8))
        wrapped.plantTwin(
            try BackupPassphraseFixture.wrap(passphrase: "the real one"), isSynchronizable: true)

        #expect(throws: Vault.VaultError.wrongPassphrase) { try vault.unlock(with: "mistyped") }
    }
}

/// Builds a wrapped record for a given passphrase, so a test can plant one that belongs to a
/// different vault.
enum BackupPassphraseFixture {
    static func wrap(passphrase: String) throws -> Data {
        try WrappedVaultKey.wrap(vaultKey: SymmetricKey(size: .bits256), passphrase: passphrase)
    }
}
