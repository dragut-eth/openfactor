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

        #expect(throws: (any Error).self) {
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
}
