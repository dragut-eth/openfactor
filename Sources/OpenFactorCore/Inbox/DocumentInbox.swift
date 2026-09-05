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
