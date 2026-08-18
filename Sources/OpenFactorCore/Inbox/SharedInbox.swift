import Foundation

/// The one place a share extension may put something, and the app may take it from.
///
/// ## What this is for
///
/// A transfer QR may contain every OTP secret in the vault, in the clear, in one image. When one
/// arrives by Messages, Mail, AirDrop or Files, the only route into OpenFactor without this is to
/// save it to Photos first, which writes it to a persistent store: with iCloud Photos enabled it
/// can be synced through iCloud to the owner's other devices and reached from iCloud.com, and
/// deleting it retains it in Recently Deleted for up to 30 days. This removes that step.
///
/// It does not remove every copy. The image still sits in the sending app's storage, and one
/// already in Photos stays there. It removes the **additional, persistent** copy.
///
/// ## Why an App Group is acceptable here, when it is not for keys
///
/// **This container is not treated as a confidentiality boundary.** Gate E1 demolished exactly
/// that assumption about Keychain access groups, and `docs/VAULT.md` classifies an App Group the
/// same way: a sibling app of the same team can be authorized into it, and one that was could
/// read the item waiting here.
///
/// That is an accepted exposure, for reasons that are all properties of the item rather than of
/// the container. It exists only during an explicit share, carries complete file protection, is
/// never synced by OpenFactor, holds no OpenFactor key material, and is deleted as soon as the
/// app consumes it. **No key or passphrase material may ever be written here**, which is an
/// invariant in `docs/VAULT.md` rather than a preference.
///
/// ## The lifecycle, which is the other half of the point
///
/// Written by the extension, taken **once** by the app, and the whole directory swept at every
/// launch. The sweep is what covers the case the delete cannot: the app never opened, or was
/// killed between the extension writing and the app reading. That is the same lifecycle the
/// export file already has, and for the same reason.
public struct SharedInbox: Sendable {

    /// Both targets read this constant rather than each spelling the group out, because a
    /// disagreement between them is a feature that silently does nothing.
    ///
    /// **The `group.` prefix is Apple's, not a style choice**, and iOS refuses an identifier
    /// without it. What follows is the domain rather than the app's bundle identifier, because
    /// the group is shared *between* targets and the app does not own it: the extension is an
    /// equal member, and `group.dev.openfactor.app` would read as the app's private group.
    ///
    /// Unlike the Keychain access group, this is cheap to rename. A Keychain item lives in the
    /// group it was written to, which is why renaming that one stranded every stored account.
    /// Nothing durable lives here: an item exists for seconds and every launch sweeps the
    /// directory, so a rename costs a re-registration and nothing else.
    public static let appGroup = "group.dev.openfactor"

    /// A subdirectory rather than the container root, so a sweep can delete everything it finds
    /// without having to know what else might live alongside it.
    static let directoryName = "Inbox"

    /// Asked for on every access, never remembered. Gate E6 measured an app update preserving
    /// container contents while moving the container, so a stored absolute path points at
    /// somewhere that no longer exists.
    private let container: @Sendable () -> URL?

    public init() {
        container = {
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: SharedInbox.appGroup)
        }
    }

    /// Injectable only so tests need no entitlement.
    init(container: @escaping @Sendable () -> URL?) {
        self.container = container
    }

    public enum InboxError: Error, Equatable, Sendable {
        /// The app group is not reachable. A missing entitlement, almost always.
        case noContainer
        case notFound
    }

    private func directory() throws(InboxError) -> URL {
        guard let base = container() else { throw .noContainer }
        return base.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    // MARK: - The extension's side

    /// Writes an item and returns the name to put in the URL.
    ///
    /// The name is a fresh UUID and carries no information: not the file's type, not its size,
    /// not where it came from. The URL that follows it is the only thing that leaves this
    /// process, and a URL can be logged, can appear in handoff, and can end up in a diagnostic
    /// bundle.
    @discardableResult
    public func write(_ data: Data) throws -> UUID {
        let directory = try directory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])

        let id = UUID()
        try data.write(to: directory.appendingPathComponent(id.uuidString), options: [
            // Unreadable while the device is locked. The app has to be opened to take it, so
            // nothing is lost by the strongest class here.
            .completeFileProtection,
            .atomic,
        ])
        return id
    }

    // MARK: - The app's side

    /// An item waiting to be collected, and when it arrived.
    public struct Pending: Sendable, Equatable {
        public let id: UUID
        public let arrived: Date
    }

    /// **How long an item is still worth presenting.**
    ///
    /// The app collects on launch rather than being sent a URL, because a share extension is not
    /// permitted to open its containing app. So the gap between sharing and collecting is however
    /// long somebody takes to open OpenFactor, which in the real flow is seconds: they shared it
    /// *in order* to import it, the sheet closed, and the next thing they do is open the app.
    ///
    /// Anything older is swept unread. Presenting an import sheet for something shared days ago
    /// would be a confusing thing to open the app into, and re-sharing costs one gesture.
    public static let freshness: TimeInterval = 10 * 60

    /// What is waiting, newest first.
    ///
    /// **Reading does not remove**, unlike `take`, because the caller has to choose before it
    /// consumes. Everything it does not choose must then be swept, which is what the app does.
    public func pending() -> [Pending] {
        guard let directory = try? directory(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }

        return names.compactMap { name -> Pending? in
            guard let id = UUID(uuidString: name) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)
            let arrived = (attributes?[.modificationDate] as? Date) ?? .distantPast
            return Pending(id: id, arrived: arrived)
        }
        .sorted { $0.arrived > $1.arrived }
    }

    /// Reads an item and removes it, whether or not the caller does anything with it.
    ///
    /// **Taking is destructive on purpose.** An import that fails, is cancelled, or crashes must
    /// not leave a transfer QR sitting in a container waiting for the next process that can read
    /// the group.
    public func take(_ id: UUID) throws -> Data {
        let url = try directory().appendingPathComponent(id.uuidString)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw InboxError.notFound
        }
        return data
    }

    /// Removes everything, for launch.
    ///
    /// Covers what `take` cannot: the app never opened after the extension wrote, or was killed
    /// between the two. Deliberately silent, because there is nothing a person could do about a
    /// failure and nothing they lose by one.
    public func sweep() {
        guard let directory = try? directory() else { return }
        guard
            let names = try? FileManager.default.contentsOfDirectory(
                atPath: directory.path)
        else { return }

        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
