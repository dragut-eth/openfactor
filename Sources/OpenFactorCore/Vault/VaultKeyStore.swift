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
        /// The directory a key was about to be written into is not excluded from backup, and
        /// saying so could not be confirmed. Nothing is written: a key that cannot be kept out
        /// of a backup is not written at all rather than written and hoped about.
        case notExcludedFromBackup
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
        // Measured before it is read, which matters less here than anywhere else and is done for
        // consistency: this file is written by this app and lives in its private container, so
        // nothing hostile is expected to put a gigabyte at that path. The class sweep that
        // followed gate A4's import findings covered every whole-file read in the project, and
        // leaving one of them to be the exception is how the class comes back.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, size > Self.keySize { throw KeyStoreError.damaged }

        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        guard data.count == Self.keySize else { throw KeyStoreError.damaged }

        repairProtection(of: url)
        return SymmetricKey(data: data)
    }

    /// Brings an already-written key up to the rules the current build writes under.
    ///
    /// **Shipping a stricter rule does not apply it to anything already on disk.** Round two of
    /// gate A4 made this concrete: the Watch in the maintainer's own pocket holds a `vault.key`
    /// written before the protection class was corrected, and every fix above governs the *next*
    /// write, which for a working device never comes. The device that most needs the fix is the
    /// one that already worked.
    ///
    /// Metadata only, deliberately. Protection class and backup exclusion are both settable on a
    /// file in place, so this never opens, rewrites, or replaces the key: there is no window here
    /// in which the key is absent or half written, and the worst outcome of a failure is the
    /// protection the device already had.
    private func repairProtection(of url: URL) {
        try? FileManager.default.setAttributes(Self.protectionAttributes, ofItemAtPath: url.path)

        let excluded = (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?
            .isExcludedFromBackup
        guard excluded != true else { return }

        // `try?` here, unlike the staging directory, and the difference is deliberate: this is a
        // repair of a key that already exists and is already readable. A repair that cannot run
        // must not stop the owner reading their own accounts, and the file is no worse than it
        // was a moment ago. The staging mark protects a key that does not exist yet, so failing
        // it silently would create the exposure rather than leave one in place.
        var marked = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? marked.setResourceValues(values)
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

        // **The key is only ever written inside a directory that is already excluded from
        // backup.** Round one found the key written and then excluded, so a kill between the two
        // left a usable unexcluded key with nothing to retry it. The first fix staged the write
        // under a temporary name and marked that, which round two pointed out fixes nothing: a
        // backup enumerates the container, not the filename, so a kill between writing the
        // staging file and marking it leaves exactly the same complete unexcluded key one path
        // along.
        //
        // Excluding the directory first is what actually closes it. Exclusion applies to a
        // directory's contents, so from the moment any key material exists on disk it is already
        // outside every backup, whatever happens next.
        let staging = try stagingDirectory()
        let pending = staging.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pending) }

        try data.write(to: pending, options: Self.writingOptions)

        // **The pending file carries the flag, not just the directory it sits in.** Directory
        // exclusion is what protects the write window, and it is not enough on its own here,
        // because `.usingNewMetadataOnly` below installs *this* file's metadata at the resting
        // path, where there is no excluded directory to sit inside. Marking it here is what makes
        // the key that ends up at `vault.key` an excluded one.
        //
        // The suite caught this: the fix for the write window broke the property the write window
        // was about, and "excluded from backups" went red the first time both ran together.
        var marked = pending
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try marked.setResourceValues(values)

        // `.usingNewMetadataOnly`, because the ordinary path is an overwrite and the default is
        // documented as preserving the original item's metadata where it can. Measured on macOS,
        // the backup exclusion of the new file did win under the default; the protection class
        // cannot be measured there at all, since macOS has no data protection, so this is the
        // difference between believing and specifying. A watch that already holds a key written
        // under the earlier, weaker rule is exactly the device this has to overwrite correctly.
        _ = try FileManager.default.replaceItemAt(
            url, withItemAt: pending, options: [.usingNewMetadataOnly])
    }

    /// A directory that is excluded from backup before anything is put in it, and swept of
    /// anything a previous run left behind.
    ///
    /// The sweep covers the case exclusion cannot: a kill between writing a pending key and
    /// replacing with it leaves that file behind. It is already excluded, so it is not a backup
    /// exposure, but a raw key sitting in the container until the app is deleted is not something
    /// to leave lying about either.
    private func stagingDirectory() throws -> URL {
        let directory = try fileURL().deletingLastPathComponent()
            .appendingPathComponent("PendingKeys", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: Self.protectionAttributes)
        }

        // **Not `try?`.** This one call is what `SECURITY.md` states unconditionally: that there
        // is no instant at which a complete key sits on disk outside the exclusion. Swallowing
        // its error would write key material into an unexcluded directory with nothing raised,
        // nothing logged, and no test able to see it, and the self-healing re-mark on the next
        // call is exactly the "it will be fixed by the following write" reasoning this finding's
        // own history says not to trust. Round three asked for it to throw; every other line in
        // `install` already can, and its caller is prepared.
        var marked = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try marked.setResourceValues(values)

        // **Read back rather than assume the write took.** Throwing on a refusal is not the same
        // as knowing the flag is set, and a review asked for the difference: refuse to write any
        // key unless the exclusion reads back true. A fresh `URL` because the one above has
        // cached what it knew before the call, which is a trap this repository has already fallen
        // into once, in a test.
        let confirmation = URL(fileURLWithPath: directory.path)
        guard try confirmation.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true
        else {
            throw KeyStoreError.notExcludedFromBackup
        }

        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }

        return directory
    }

    /// Complete protection on the directory too, so a file created inside it starts protected
    /// rather than becoming so.
    static var protectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS) || os(watchOS) || os(tvOS)
            [.protectionKey: FileProtectionType.complete]
        #else
            [:]
        #endif
    }

    /// Complete protection wherever the platform has it.
    ///
    /// **This used to borrow `SharedInbox.writingOptions`, and that was a real defect.** That
    /// helper is `#if os(iOS)`, which is narrower than the platforms this file supports, so the
    /// watch wrote the vault key with `.atomic` alone beneath a comment promising `.complete`.
    /// The default class is complete-until-first-unlock, which stays readable after the first
    /// unlock of the boot, including while the wrist is locked, which is the state the
    /// protection was chosen for. Found in gate A4 by every engine that could see both files.
    ///
    /// `.complete` rather than "the strongest available", which is a superlative a second
    /// implementation could satisfy two ways. The consequence is deliberate: the key is
    /// unreadable while the device is locked, so nothing reads the vault in the background.
    /// This app declares no background modes, so nothing is lost.
    ///
    /// macOS has no data protection and was measured refusing the option outright with `EPERM`
    /// after days of silently accepting it, so it is only ever `.atomic` there. macOS is the
    /// test host and never a device this key lives on.
    static var writingOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS) || os(tvOS)
            [.completeFileProtection, .atomic]
        #else
            [.atomic]
        #endif
    }

    /// Removes the key, which makes every account on this device unreadable until a key is
    /// installed again.
    ///
    /// This is not a way to erase accounts, and must not be offered as one: the ciphertext stays
    /// in the Keychain and syncs, so another device still reads it and this one recovers the
    /// moment a passphrase is entered. Erasing accounts is `EraseAccountsView`'s job and deletes
    /// the items themselves.
    public func discard() throws {
        // **The staging directory goes too.** A review noticed that an install killed between
        // writing a pending key and replacing with it leaves that key behind, and erasing the
        // vault did not remove it: the accounts it opened are gone, so the harm is near nil, but
        // a raw key sitting in the container after somebody chose to erase everything is not a
        // thing to leave lying about. The sweep on the next install would have collected it, and
        // after an erase there may never be a next install.
        let staging = try fileURL().deletingLastPathComponent()
            .appendingPathComponent("PendingKeys", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)

        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
