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
        /// The item is larger than anything this app will read. Removed rather than left.
        case tooLarge
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
            attributes: Self.protectionAttributes)

        // **Excluded before anything is put in it.** A review found inbox items eligible for
        // device backup: an item lives for seconds, but a backup taken during those seconds
        // carries a QR image of every secret in somebody's authenticator into iTunes or iCloud,
        // where nothing sweeps it. The directory carries the flag rather than each file, and it
        // is marked before the write for the same reason the vault key's staging directory is:
        // a mark applied afterwards leaves a window with nothing to close it.
        var marked = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? marked.setResourceValues(values)

        let id = UUID()
        try data.write(
            to: directory.appendingPathComponent(id.uuidString), options: Self.writingOptions)
        return id
    }

    /// Complete protection on iOS, and nothing on macOS, **because macOS refuses the option**.
    ///
    /// Data protection classes do not exist on macOS. For two days this machine silently
    /// accepted the option anyway, even reporting the attribute back, and then began refusing
    /// it with `EPERM` mid-evening, which failed every writing test in this file while the code
    /// was untouched. The honest reading is that the option is meaningless off iOS and only
    /// sometimes tolerated, so it is passed exactly where it means something. iOS behavior is
    /// unchanged: unreadable while the device is locked, and the app must be open to take an
    /// item, so nothing is lost by the strongest class.
    static var writingOptions: Data.WritingOptions {
        #if os(iOS)
            [.completeFileProtection, .atomic]
        #else
            [.atomic]
        #endif
    }

    static var protectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
            [.protectionKey: FileProtectionType.complete]
        #else
            [:]
        #endif
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
    public func pending(now: Date = Date()) -> [Pending] {
        guard let directory = try? directory(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }

        return names.compactMap { name -> Pending? in
            guard let id = UUID(uuidString: name) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)
            // **Clamped, because the timestamp is not this app's.** A review pointed out that
            // freshness was read straight off the file, and a modification date in the future
            // makes an item sort ahead of everything and look newer than anything that could
            // actually have arrived. Nothing on the device should be able to claim it arrived
            // after now.
            let stamped = (attributes?[.modificationDate] as? Date) ?? .distantPast
            return Pending(id: id, arrived: min(stamped, now))
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

        // **The size is asked of the file system before the read.** All three engines found this
        // unbounded: whatever was in the container was copied into memory, and the bound, where
        // there was one, came afterwards. The item is removed either way, so an oversized one is
        // taken off the device rather than left for the next attempt.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let size, !ImportLimits.isWorthLoading(fileSize: size) { throw InboxError.tooLarge }

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

    /// How long an item may sit in the inbox before a launch sweeps it regardless.
    ///
    /// Long enough that the ordinary path is untouched: the extension writes, the person is
    /// carried into the app, and the collection happens in seconds. Short enough that an item
    /// nobody collected does not sit in a shared container for the rest of the day.
    public static let staleAfter: TimeInterval = 5 * 60

    /// Removes what nobody is coming for, and leaves what somebody just shared.
    ///
    /// **All three engines found the sweep unreachable in the case it exists for.** `SharedInbox`
    /// says the directory is swept at every launch and `SECURITY.md` says leftovers are swept when
    /// OpenFactor launches, but the only sweep sat inside the collection path, which refuses to
    /// run until the scene is active, the lock is open, the vault is open and no arrival is
    /// pending. An image shared to a locked phone that was never unlocked again stayed there.
    ///
    /// This runs at launch with none of those conditions, and it cannot eat the item somebody
    /// just shared, because that one is seconds old.
    public func sweepStale(now: Date = Date()) {
        for item in pending(now: now) where now.timeIntervalSince(item.arrived) > Self.staleAfter {
            guard let url = try? directory().appendingPathComponent(item.id.uuidString) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
