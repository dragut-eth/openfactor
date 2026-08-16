import CryptoKit
import Foundation

/// The vault key, on disk, in the one place another app cannot reach.
///
/// Gate E1 measured that a Keychain access group is not a boundary between apps of one team, and
/// gate E4 measured that a container is: a sibling holding the victim's exact path was refused by
/// the kernel with `EPERM` and could not even enumerate. This type is where that asymmetry is
/// spent. The ciphertext lives in the Keychain because it has to sync; the key lives here because
/// nothing else can read it.
///
/// ## The path is never remembered
///
/// **Every access asks `FileManager` again**, and that is a rule rather than a style. Gate E6
/// measured an app update preserving the file byte for byte while the container changed identity:
/// the data came back from a different directory. Anything that caches or persists the absolute
/// path breaks at the first update, and breaks by pointing at a container that no longer exists,
/// which fails silently rather than loudly.
///
/// `docs/audits/E6-container-durability.md` has the two container identifiers side by side.
///
/// ## What is deliberately absent
///
/// No accessor returns the path, and nothing stores it. The key is never written to the Keychain,
/// never synchronised, never placed in an App Group or ubiquitous container, and never logged.
/// Those are invariants in `docs/VAULT.md` rather than preferences, and several are checkable.
public struct VaultKeyStore: Sendable {

    /// The file's name inside the container. Deliberately dull: a container listing is only
    /// reachable by this app, but a name is also what appears in a crash report path.
    static let fileName = "vault.key"

    static let keySize = 32

    /// Where the directory is, asked for **on every call**. Injectable only so tests can use a
    /// temporary directory; production passes nothing and the default reads `FileManager` each
    /// time, which is the behaviour E6 requires.
    private let directory: @Sendable () -> URL?

    public init() {
        directory = {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        }
    }

    init(directory: @escaping @Sendable () -> URL?) {
        self.directory = directory
    }

    public enum KeyStoreError: Error, Equatable {
        case noContainer
        case randomnessUnavailable
        case damaged
    }

    private func fileURL() throws -> URL {
        guard let base = directory() else { throw KeyStoreError.noContainer }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(Self.fileName)
    }

    // MARK: - Reading

    public var exists: Bool {
        guard let url = try? fileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The key, or `nil` when this device has not been given one yet.
    ///
    /// **Absent is not damaged.** A device that has ciphertext and no key is the ordinary state
    /// of a fresh install or a new phone, and the interface must offer the passphrase rather than
    /// report a fault. Only a file that exists and is the wrong size is a fault.
    public func load() throws -> SymmetricKey? {
        let url = try fileURL()
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        guard data.count == Self.keySize else { throw KeyStoreError.damaged }
        return SymmetricKey(data: data)
    }

    // MARK: - Writing

    /// Generates a vault key and stores it. Used once, when a vault is created.
    public func create() throws -> SymmetricKey {
        var bytes = Data(repeating: 0, count: Self.keySize)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Self.keySize, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw KeyStoreError.randomnessUnavailable }

        let key = SymmetricKey(data: bytes)
        try install(key)
        return key
    }

    /// Stores a key this device was given: unwrapped from a passphrase, or handed over by a
    /// paired phone during watch provisioning.
    public func install(_ key: SymmetricKey) throws {
        let url = try fileURL()
        let data = key.withUnsafeBytes { Data($0) }

        #if os(iOS) || os(watchOS) || os(tvOS)
            // `.complete` rather than "the strongest available", which is a superlative a second
            // implementation could satisfy two ways. The consequence is deliberate: the key is
            // unreadable while the device is locked, so nothing reads the vault in the
            // background. This app declares no background modes, so nothing is lost.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            // macOS, which is only ever the test host. Data protection classes do not exist
            // here, so the tests that matter for it are the ones that run on a device.
            try data.write(to: url, options: [.atomic])
        #endif

        // Excluded so a restored device has ciphertext and no key, and asks for the passphrase.
        // Letting the key ride along would make restores seamless and would mean the passphrase
        // is never exercised, never noticed as important, and absent when it is finally needed.
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    /// Removes the key, which makes every account on this device unreadable until a key is
    /// installed again.
    ///
    /// This is not a way to erase accounts, and must not be offered as one: the ciphertext stays
    /// in the Keychain and syncs, so another device still reads it and this one recovers the
    /// moment a passphrase is entered. Erasing accounts is `EraseAccountsView`'s job and deletes
    /// the items themselves.
    public func discard() throws {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
