import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The key on disk, and the rules that keep it reachable to this app and nobody else.
///
/// **What these tests cannot see, stated first.** They run on macOS, where data protection
/// classes do not exist, so nothing here proves `.complete` is applied. That was measured on
/// hardware instead, in `docs/audits/E6-container-durability.md`, where the attribute was written
/// and read back as `NSFileProtectionComplete`. A test that quietly passed on a platform with no
/// data protection would be the check-that-promises-more-than-it-delivers this project has found
/// three times, so it is named here rather than implied.
@Suite("Vault key store")
struct VaultKeyStoreTests {

    /// A fresh directory per test, and a provider that is **asked every time**, which is what the
    /// production default does. A test holding one URL would not exercise the rule E6 imposed.
    private func makeStore() -> (VaultKeyStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)")
        return (VaultKeyStore(directory: { dir }), dir)
    }

    // MARK: - The ordinary life of a key

    @Test("A device with no key says so rather than failing")
    func absentIsNotAnError() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(!store.exists)
        #expect(try store.load() == nil)
    }

    @Test("A created key is 256 bits and comes back")
    func createAndLoad() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let created = try store.create()
        #expect(created.withUnsafeBytes { Data($0) }.count == 32)
        #expect(store.exists)

        let loaded = try #require(try store.load())
        #expect(
            loaded.withUnsafeBytes { Data($0) } == created.withUnsafeBytes { Data($0) })
    }

    /// Not a test of the CSPRNG, which cannot be tested from here. It catches the failure that
    /// actually happens, which is a key generated once and reused.
    @Test("Two created keys are different keys")
    func createIsRandom() throws {
        var seen: Set<Data> = []

        for _ in 0..<16 {
            let (store, dir) = makeStore()
            defer { try? FileManager.default.removeItem(at: dir) }
            seen.insert(try store.create().withUnsafeBytes { Data($0) })
        }

        #expect(seen.count == 16)
    }

    @Test("A key handed to this device is stored as given")
    func installRoundTrips() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let given = SymmetricKey(data: Data(repeating: 0x3C, count: 32))
        try store.install(given)

        let loaded = try #require(try store.load())
        #expect(loaded.withUnsafeBytes { Data($0) } == Data(repeating: 0x3C, count: 32))
    }

    @Test("Installing replaces rather than appends")
    func installReplaces() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try store.install(SymmetricKey(data: Data(repeating: 0x01, count: 32)))
        try store.install(SymmetricKey(data: Data(repeating: 0x02, count: 32)))

        let loaded = try #require(try store.load())
        #expect(loaded.withUnsafeBytes { Data($0) } == Data(repeating: 0x02, count: 32))
    }

    @Test("Discarding removes the key, and discarding twice is not an error")
    func discardIsIdempotent() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.create()
        try store.discard()
        #expect(!store.exists)
        #expect(try store.load() == nil)

        #expect(throws: Never.self) { try store.discard() }
    }

    // MARK: - What must not pass silently

    /// Absent is ordinary; the wrong size is not. A short file means something wrote here that
    /// was not this type, and treating it as a key would produce an unreadable vault with no
    /// explanation.
    @Test("A file of the wrong size is a fault rather than a key", arguments: [0, 16, 31, 33, 64])
    func wrongSizeIsDamaged(count: Int) throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0, count: count)
            .write(to: dir.appendingPathComponent(VaultKeyStore.fileName))

        #expect(throws: VaultKeyStore.KeyStoreError.damaged) { try store.load() }
    }

    @Test("No container is an error rather than a crash")
    func missingContainerIsHandled() {
        let store = VaultKeyStore(directory: { nil })

        #expect(!store.exists)
        #expect(throws: VaultKeyStore.KeyStoreError.noContainer) { try store.load() }
        #expect(throws: VaultKeyStore.KeyStoreError.noContainer) { _ = try store.create() }
    }

    // MARK: - The rules from the probes

    /// E6 measured an app update preserving the file while the container changed identity, so a
    /// remembered path points at somewhere that no longer exists. This asserts the store follows
    /// a directory that moves, which a cached URL could not.
    @Test("The key is found again after its container moves")
    func followsAMovedContainer() throws {
        let first = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)")
        let second = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        // The provider answers differently after the "update", exactly as the real one would.
        nonisolated(unsafe) var current = first
        let store = VaultKeyStore(directory: { current })

        let key = try store.create()

        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: first.appendingPathComponent(VaultKeyStore.fileName),
            to: second.appendingPathComponent(VaultKeyStore.fileName))
        current = second

        let loaded = try #require(try store.load())
        #expect(loaded.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) })
    }

    /// The exclusion is what makes a restored device ask for the passphrase instead of silently
    /// recovering, which is the whole recovery story. Readable on macOS, and measured on hardware
    /// in E6 as well.
    @Test("The key file is excluded from backups")
    func excludedFromBackup() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try store.create()

        let url = dir.appendingPathComponent(VaultKeyStore.fileName)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }
}
