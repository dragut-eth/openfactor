import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The vault's lifecycle, and the three device states it exists to tell apart.
///
/// The distinction these tests are really about is `absent` versus `locked`. Confusing them is
/// the failure that cannot be recovered from: asking somebody to type a passphrase that was
/// never issued, or issuing a second one and stranding everything sealed under the first.
@Suite("Vault lifecycle")
struct VaultTests {

    private func makeVault() -> (Vault, VaultKeyStore, WrappedKeyStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        let wrapped = WrappedKeyStore(service: "app.openfactor.tests.\(UUID().uuidString)")
        return (Vault(keys: keys, wrapped: wrapped), keys, wrapped)
    }

    // MARK: - The three states

    @Test("A device with nothing at all reports absent")
    func nothingIsAbsent() {
        let (vault, _, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        #expect(vault.state() == .absent)
    }

    @Test("Creating a vault opens it")
    func creatingOpens() throws {
        let (vault, _, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        #expect(vault.state() == .open)
    }

    /// The state that matters most: ciphertext has arrived and this device has no key. It must
    /// never read as a fresh start, because creating a second vault here would strand everything
    /// sealed under the first.
    @Test("A device with a record and no key is locked, not absent")
    func recordWithoutKeyIsLocked() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try keys.discard()

        #expect(vault.state() == .locked)
        #expect(vault.state() != .absent)
    }

    // MARK: - Creating

    @Test("Creation returns a passphrase in the form it is shown, and stores it nowhere")
    func createReturnsADisplayablePassphrase() throws {
        let (vault, _, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        let (_, passphrase) = try vault.create()

        #expect(passphrase == BackupPassphrase.grouped(
            String(decoding: BackupPassphrase.canonical(passphrase), as: UTF8.self)))
        #expect(passphrase.filter { $0 == "-" }.count == 5)
    }

    @Test("Two vaults never share a key or a passphrase")
    func creationIsFresh() throws {
        var keys: Set<Data> = []
        var passphrases: Set<String> = []

        for _ in 0..<6 {
            let (vault, _, wrapped) = makeVault()
            defer { try? wrapped.delete() }

            let (key, passphrase) = try vault.create()
            keys.insert(key.withUnsafeBytes { Data($0) })
            passphrases.insert(passphrase)
        }

        #expect(keys.count == 6)
        #expect(passphrases.count == 6)
    }

    // MARK: - Unlocking

    @Test("The passphrase from creation unlocks another device")
    func passphraseUnlocks() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        let (original, passphrase) = try vault.create()

        // A second device: the same Keychain record, no key of its own.
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        let secondDevice = Vault(
            keys: VaultKeyStore(directory: { elsewhere }), wrapped: wrapped)

        #expect(secondDevice.state() == .locked)
        try secondDevice.unlock(with: passphrase)
        #expect(secondDevice.state() == .open)

        let recovered = try #require(try VaultKeyStore(directory: { elsewhere }).load())
        #expect(
            recovered.withUnsafeBytes { Data($0) } == original.withUnsafeBytes { Data($0) })
        _ = keys
    }

    @Test("A wrong passphrase says so and leaves the device locked")
    func wrongPassphraseIsRefused() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try keys.discard()

        #expect(throws: Vault.VaultError.wrongPassphrase) {
            try vault.unlock(with: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF")
        }
        #expect(vault.state() == .locked)
    }

    /// Absent is not a wrong passphrase, and reporting it as one would send somebody hunting for
    /// a string that does not exist.
    @Test("Unlocking a device with no record says there is nothing to unlock")
    func unlockingNothingIsItsOwnAnswer() {
        let (vault, _, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        #expect(throws: Vault.VaultError.nothingToUnlock) {
            try vault.unlock(with: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF")
        }
    }

    // MARK: - Replacing the passphrase

    @Test("A replaced passphrase opens the vault and the old one stops working")
    func replacingThePassphrase() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        let (_, first) = try vault.create()
        let second = try vault.replacePassphrase()

        #expect(first != second)

        try keys.discard()
        #expect(throws: Vault.VaultError.wrongPassphrase) { try vault.unlock(with: first) }
        #expect(throws: Never.self) { try vault.unlock(with: second) }
    }

    /// The property that makes replacement cheap, and the reason it is not revocation: the vault
    /// key is unchanged, so every account stays readable without being re-encrypted.
    @Test("Replacing the passphrase does not rotate the vault key")
    func replacementKeepsTheSameKey() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        let (original, _) = try vault.create()
        _ = try vault.replacePassphrase()

        let after = try #require(try keys.load())
        #expect(
            after.withUnsafeBytes { Data($0) } == original.withUnsafeBytes { Data($0) },
            "rewrapping must not change the key, which is also why it is not revocation")
    }

    // MARK: - Destroying

    @Test("Destroying leaves nothing behind and returns the device to absent")
    func destroyRemovesEverything() throws {
        let (vault, keys, wrapped) = makeVault()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try vault.destroy()

        #expect(vault.state() == .absent)
        #expect(try keys.load() == nil)
        #expect(try wrapped.load() == nil)
    }
}
