import Foundation

/// The copies iOS makes when a document is opened into this app, and their removal.
///
/// **A file opened into the app is a copy the app owns, and it used to be kept forever.**
/// `LSSupportsOpeningDocumentsInPlace` is false, so "Open in OpenFactor" hands over a copy in
/// `Documents/Inbox`, a directory Apple backs up. The import read it and never looked at it again.
/// Every secret in a plaintext export therefore sat in the clear, in a backed-up location, after
/// the import, after the original was deleted, and after the accounts were erased. Audit X3 found
/// it as OF-X3-01, and by this project's threat model it is the most serious thing three audits
/// have found, because it needs no adversary: it is a supported path leaving secrets unencrypted
/// somewhere the app never looks.
///
/// **Only what this app owns, and nothing else.** A document picker hands over a security scoped
/// URL to somebody else's file, and deleting that would be destroying the person's own export on
/// their own disk. So every removal here is gated on the path being inside the inbox directory,
/// resolved rather than compared as text, and a URL that is not is left exactly where it is.
///
/// **The directory is kept out of backups as well, since audit X4.** Removing on read and
/// sweeping on foreground left one path open: a copy delivered during a locked cold start is
/// neither read, because the import screen is not in the tree, nor swept, because it is younger
/// than a minute, and a process killed in that state leaves it for the next backup.
/// `excludeFromBackup` puts the flag on the directory the way the shared inbox and the vault key
/// directory already carry theirs.
///
/// **Located through `FileManager` on every call, never remembered.** An update moves the
/// container, measured in E6; a stored absolute path would point at a directory that is no longer
/// there, and would do so by failing quietly.
public struct DocumentInbox: Sendable {

    /// The subdirectory iOS writes opened documents into. Apple's name, not this project's.
    public static let directoryName = "Inbox"

    /// How old a file has to be before the launch sweep removes it. A delivery can land while
    /// the app is coming forward, and this is what keeps the sweep from deleting a file the import
    /// has not read yet. Same shape as `SharedInbox.freshness`, for the same reason.
    public static let settledAge: TimeInterval = 60

    private let documents: @Sendable () -> URL?

    public init() {
        documents = {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }

    /// Injectable only so tests can use a temporary directory.
    init(documents: @escaping @Sendable () -> URL?) {
        self.documents = documents
    }

    private var directory: URL? {
        documents()?.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// Whether this URL is a copy this app owns: a file inside its own inbox.
    ///
    /// The candidate is resolved, so a symlink or a `..` in it cannot make a foreign path look
    /// like an owned one. The inbox path itself is a prefix and a separator, so a sibling named
    /// `InboxArchive` does not match.
    ///
    /// **The inbox is anchored under the canonical Documents directory and must be a real
    /// directory there.** The first version resolved both sides, which let the trusted root move:
    /// replace `Documents/Inbox` itself with a link to a sibling and every file in the sibling was
    /// owned, because the comparison followed the link. X3's verification round planted exactly
    /// that. It needs write access inside the private container, which E4 measured to be beyond a
    /// sibling's reach, so it is hardening rather than a hole, and it costs one comparison: if the
    /// inbox path resolves anywhere other than itself, nothing is owned.
    public func owns(_ url: URL) -> Bool {
        guard url.isFileURL, let documents = documents() else { return false }
        let root = documents.standardizedFileURL.resolvingSymlinksInPath()
        let inbox = root.appendingPathComponent(Self.directoryName, isDirectory: true)
            .standardizedFileURL.path
        guard URL(fileURLWithPath: inbox).resolvingSymlinksInPath().path == inbox else {
            return false
        }
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate.hasPrefix(inbox + "/") && candidate.count > inbox.count + 1
    }

    /// Keeps the inbox directory, and so every copy iOS drops into it, out of device backups.
    ///
    /// **The directory carries the flag, because the app never sees a copy before it exists.**
    /// iOS writes the copy, so there is no write here to refuse the way the shared inbox refuses
    /// its own. What can be done is to have the directory already marked when the copy lands,
    /// and to re-mark it at every launch, foreground and arrival, since the system may recreate
    /// it. A backup honours the flag on the directory for everything inside it. Audit X4,
    /// OF-X4-01: a copy used to wait here through a locked cold start, unread because the
    /// import screen was not in the tree and unswept because it was younger than a minute, in a
    /// directory with no flag, where the shared inbox and the vault key directory both had one.
    /// Since the second half of that fix the copy is read and removed at arrival, so what the
    /// mark covers now is what remains: a process that dies before the arrival handler runs, and
    /// the very first delivery on a fresh install, which iOS writes before the launch task can
    /// mark anything.
    ///
    /// **Best effort, and honest about it.** The return value says whether the mark reads back;
    /// callers in the app cannot do anything useful with a failure, since refusing the directory
    /// would mean deleting a delivery before it is read. The mark is the second line; the first
    /// is removing the copy on read, and the next is taking the bytes out at arrival.
    ///
    /// **Not through a redirect.** The same check `owns` makes: if the inbox path resolves
    /// anywhere other than itself, nothing is created and nothing is marked.
    @discardableResult
    public func excludeFromBackup() -> Bool {
        guard let documents = documents() else { return false }
        let root = documents.standardizedFileURL.resolvingSymlinksInPath()
        let inbox = root.appendingPathComponent(Self.directoryName, isDirectory: true)
            .standardizedFileURL
        guard URL(fileURLWithPath: inbox.path).resolvingSymlinksInPath().path == inbox.path else {
            return false
        }

        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: inbox.path, isDirectory: &isDirectory) {
            guard (try? manager.createDirectory(
                at: inbox, withIntermediateDirectories: false)) != nil
            else { return false }
        } else if !isDirectory.boolValue {
            return false
        }

        var marked = inbox
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        guard (try? marked.setResourceValues(values)) != nil else { return false }

        // Read back on a fresh URL, because the one above has cached what it knew before the call.
        let confirmation = URL(fileURLWithPath: inbox.path)
        return (try? confirmation.resourceValues(forKeys: [.isExcludedFromBackupKey]))?
            .isExcludedFromBackup == true
    }

    /// Removes an owned copy. A URL this app does not own is left where it is.
    ///
    /// Best effort by design: the bytes have already been read by the time this is called, so a
    /// removal that fails costs the same as before this type existed, and the launch sweep is the
    /// second chance.
    public func discard(_ url: URL) {
        guard owns(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes files in the inbox older than `settledAge`. Run when the app comes forward, so a
    /// copy left by a killed process, or by a build before this type existed, does not outlive it.
    public func sweep(now: @Sendable () -> Date = { Date() }) {
        sweep(olderThan: Self.settledAge, now: now)
    }

    /// Removes every file in the inbox, whatever its age. For erasing, where the person has just
    /// asked for their secrets to be gone and a recent copy is exactly what must not survive.
    public func sweepAll() {
        sweep(olderThan: 0, now: { Date.distantFuture })
    }

    private func sweep(olderThan age: TimeInterval, now: @Sendable () -> Date) {
        guard let directory else { return }
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }

        for name in names {
            let url = directory.appendingPathComponent(name)
            guard owns(url),
                let attributes = try? manager.attributesOfItem(atPath: url.path),
                (attributes[.type] as? FileAttributeType) == .typeRegular
            else { continue }
            // The file's own timestamp, then the clock, in that order, for the reason
            // `SharedInbox.sweepStale` records: the other order judges a file that landed mid
            // pass against a moment before it existed.
            let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
            guard now().timeIntervalSince(modified) >= age else { continue }
            try? manager.removeItem(at: url)
        }
    }
}
