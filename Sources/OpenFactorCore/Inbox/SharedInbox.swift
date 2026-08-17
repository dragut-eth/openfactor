import Foundation

/// The one place a share extension may put something, and the app may take it from.
///
/// ## What this is for
///
/// A transfer QR is every secret its owner has, in the clear, in one image. When one arrives by
/// Messages, Mail, AirDrop or Files, the only route into OpenFactor without this is to save it to
/// Photos first, which is the worst resting place available: long lived, searchable, and synced
/// to iCloud Photos. This removes that step.
///
/// It does not remove every copy. The image still sits in the sending app's storage, and one
/// already in Photos stays there. It removes the **additional** copy.
///
/// ## Why an App Group is acceptable here, when it is not for keys
///
/// **An App Group is a grant, not a boundary.** Gate E1 demolished exactly this assumption about
/// Keychain access groups, and `docs/VAULT.md` classifies an App Group the same way: a sibling
/// app of the same team can be authorized into it. Nothing here relies on it being private.
///
/// What makes it acceptable is what lands in it. **An image the sender already had**, which is
/// sitting in Messages or Mail regardless, held for seconds, with complete file protection, never
/// synced. A sibling that could read this group would learn a QR code it could have read from the
/// original attachment. **No key or passphrase material may ever be written here**, which is an
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
    public static let appGroup = "group.dev.openfactor.app"

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
