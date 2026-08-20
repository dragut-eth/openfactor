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
/// Written by the extension, taken **once** by the app, and swept whenever the app comes forward.
/// The sweep removes what is older than `staleAfter` rather than everything, so it cannot take the
/// item somebody shared a moment ago, and what it does take is what nobody came back for: the app
/// never opened, or was killed between the extension writing and the app reading. That is the same
/// lifecycle the export file already has, and for the same reason.
///
/// **The sweep is driven by the app coming forward, not by a clock.** An item is removed on the
/// first sweep after `staleAfter`, which is not the same as being removed at `staleAfter`: a phone
/// that never opens this app again never runs one.
///
/// **Sweeping is two operations and they follow different rules.** `sweepStale` collects garbage
/// and decides by age. `sweep(_:)` supersedes a set the caller has already chosen against and
/// decides by identity. Writing the second as "empty the directory" is what makes it delete the
/// arrival that turned up while the caller was deciding.
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
    /// Nothing durable lives here: an item exists for as long as it takes somebody to confirm
    /// an import, and until the first sweep after `staleAfter` removes it unread, so a rename costs a
    /// re-registration and nothing else.
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
        /// The inbox directory could not be kept out of device backups, so nothing was written
        /// into it. A QR of every secret is not worth writing on the hope that it is excluded.
        case notExcludedFromBackup
        /// The inbox path is not a directory this app can open: missing, not a directory, or a
        /// symbolic link. Nothing is written into something that may not be ours.
        case directoryNotOurs
    }

    private func directory() throws(InboxError) -> URL {
        guard let base = container() else { throw .noContainer }
        return base.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    // MARK: - The extension's side

    /// Writes an item and returns the name to put in the URL.
    ///
    /// The name is a fresh UUID and carries no information: not the file's type, not its size,
    /// not where it came from. **Nothing carries it out of this process**: the identifier is
    /// returned and the extension discards it, because the app finds the item by listing the
    /// directory rather than by being told. This comment used to describe a URL scheme that
    /// carried the identifier to the app, which was removed; a review found the sentence still
    /// here, describing a mechanism that no longer exists.
    @discardableResult
    public func write(_ data: Data) throws -> UUID {
        let directory = try directory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: Self.protectionAttributes)

        // **Excluded before anything is put in it, and the write is refused if it is not.** An
        // item is usually collected within seconds, but it may sit until the first sweep after
        // `staleAfter`, and a backup taken at any point in that window carries a QR image of
        // every secret in somebody's authenticator into iCloud, where nothing sweeps it. The
        // directory carries the flag rather than each file, and it is marked before the write for
        // the same reason the vault key's staging directory is: a mark applied afterwards leaves
        // a window with nothing to close it.
        //
        // **Failing to exclude refuses the write rather than writing anyway.** Failing open here
        // means any metadata failure that does not also stop ordinary writes produces a
        // backup-eligible image of every seed, silently. `VaultKeyStore` refuses to write a key
        // it cannot exclude, and there is no argument for holding this to a weaker rule.
        var marked = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try marked.setResourceValues(values)

        // Read back rather than trust the write, on a fresh URL because the one above has cached
        // what it knew before the call.
        let confirmation = URL(fileURLWithPath: directory.path)
        guard try confirmation.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true
        else {
            throw InboxError.notExcludedFromBackup
        }

        // **The directory is opened before it is written into, and the write is refused if that
        // fails.** A group is not a confidentiality boundary, so `Inbox` can be replaced with a
        // symbolic link by a sibling, and `createDirectory` above follows one happily. This
        // catches a directory already substituted. It does not catch a substitution made between
        // here and the write below, which is why the sweep and the read hold a descriptor instead
        // of trusting a check like this one.
        guard InboxDirectory(at: directory) != nil else { throw InboxError.directoryNotOurs }

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
    public func pending(now: @Sendable () -> Date = { Date() }) -> [Pending] {
        guard let directory = try? directory(), let handle = InboxDirectory(at: directory)
        else { return [] }

        return handle.names().compactMap { name -> Pending? in
            guard let id = UUID(uuidString: name) else { return nil }

            // **An entry whose age cannot be read is not a candidate.** The alternative is to
            // invent one, and an invented age is not evidence: `.distantPast` here would make an
            // unreadable entry sort last and then sit inside the identifier set a collection
            // supersedes, so it would be deleted for an age nobody measured. It stays instead,
            // which costs an entry nobody can stat sitting in the directory.
            //
            // **And a name is not enough to make something an item.** A sibling can create a
            // directory with a canonical UUID name. Admitted, it sorts by its own timestamp and
            // becomes the thing a collection reaches for; the read then refuses it because it is
            // not a regular file, and the removal that follows refuses it because `unlinkat` does
            // not take directories. Every one of those refusals is correct, and the result is a
            // genuine share sitting unseen behind something that cannot be collected and cannot
            // be removed. The candidate is what should never have existed.
            //
            // A directory therefore stays where it is, unlistable as an item and unremovable by
            // the sweep, which is an accumulation a hostile sibling can already cause directly.
            // Everything else it might plant, a link or a pipe or a socket, is not an item here
            // and is still swept by age.
            guard let entry = handle.entry(name), entry.isRegularFile else { return nil }
            let stamped = entry.modified

            // **The clock is read after the file, not before the directory.** A listing that
            // samples the clock at entry judges an item that lands mid-pass against a moment
            // before it existed: its honest timestamp is later than the sample, which is exactly
            // the shape of a plant stamped in 2090, and nothing can tell the two apart.
            //
            // Read after the stat, a share that just landed is at or before the reading and is
            // ordinary. A plant stamped tomorrow is still ahead of every reading and is still
            // refused. No tolerance window is involved: the fix is the order of two calls.
            let observed = now()

            // **A timestamp after the observation is refused, not clamped.** Clamping to the
            // observation is inert: the value is recomputed on every read, so a file stamped in
            // 2090 reports an age of zero forever. It sorts ahead of a genuine share, passes the
            // freshness test, and can never satisfy a sweep asking whether an age exceeds a
            // threshold. **The item the sweep exists to remove becomes the one it can never
            // remove.** Treated as arriving before everything, it sorts last and is immediately
            // sweepable.
            let arrived = stamped > observed ? Date.distantPast : stamped
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
        guard let directory = try? directory(), let handle = InboxDirectory(at: directory) else {
            throw InboxError.notFound
        }
        let name = id.uuidString
        defer { handle.remove(name) }

        // **One open, one bounded read, relative to a directory this app opened.** The name alone
        // does not promise a regular file: a sibling with access to this container can create a
        // named pipe, and opening one blocks until a writer appears, on the main actor, with the
        // removal above never reached. The primitive refuses anything that is not a regular file
        // before it reads a byte.
        //
        // Bounded at the image policy, since what the extension writes here is an image. The
        // archive ceiling would be four megabytes of slack nothing in this path can use.
        do {
            return try handle.read(name, limit: ImportLimits.policyBytes)
        } catch .tooLarge {
            throw InboxError.tooLarge
        } catch {
            throw InboxError.notFound
        }
    }

    /// Removes exactly these items, whatever their age.
    ///
    /// **This is supersession rather than collection**, and the two must not be one operation.
    /// Collecting garbage asks how old a file is. Superseding asks whether a newer arrival has
    /// replaced this one, which is a question about a set the caller already holds and not a
    /// question about the directory. A supersede written as "empty the directory" deletes
    /// whatever arrived between the caller's decision and the deletion, and deletes it precisely
    /// because it is too new to have been part of the decision.
    ///
    /// So the caller passes the identifiers it read, and files that arrived after that reading
    /// survive to be presented. Removing a name that is already gone is not an error and is not
    /// reported: there is nothing a person could do about it and nothing they lose by it.
    public func sweep(_ ids: [UUID]) {
        guard let directory = try? directory(), let handle = InboxDirectory(at: directory) else {
            return
        }
        for id in ids { handle.remove(id.uuidString) }
    }

    /// How long an item may sit in the inbox before a sweep removes it regardless.
    ///
    /// **The same number as `freshness`, and that is the point.** Two different numbers give an
    /// item an age at which it is worth presenting by one rule and deleted unread by the other,
    /// and which happens depends on whether iOS has kept the process alive. One idea, one
    /// constant: an item is removed exactly when it stops being worth presenting.
    public static let staleAfter = freshness

    /// Removes what nobody is coming for, and leaves what somebody just shared.
    ///
    /// **This is the collection half, and it runs on nothing but the app coming forward.** Not
    /// inside the collection path, which refuses to run until the scene is active, the lock is
    /// open, the vault is open and no arrival is pending: an image shared to a phone that is
    /// locked and never unlocked again would stay there under every one of those conditions.
    ///
    /// It runs on every foreground rather than once per process, so the threshold is a deadline
    /// and not a condition evaluated at launch.
    public func sweepStale(now: @Sendable () -> Date = { Date() }) {
        guard let directory = try? directory(), let handle = InboxDirectory(at: directory) else {
            return
        }

        for name in handle.names() {
            // **Each file's own timestamp, and then a clock read after it.** Both halves are the
            // rule. Reading the timestamp late and comparing it against a clock sampled before
            // the directory was listed judges an item that landed mid-pass against a moment
            // before it existed, so its honest stamp reads as the future and the branch below
            // deletes it as ancient. The order of the two calls is the whole of it.
            //
            // **Including names this app did not write.** Deleting a foreign name on sight was
            // the stricter rule, and it collides with the atomic write it shares the directory
            // with: `Data.write(options: .atomic)` puts a temporary file alongside the real one
            // and renames it, and that temporary name is exactly a name this app did not write.
            // In a group whose only members are this app's own targets, the foreign name deleted
            // on sight is almost always the extension's own half-finished write. Age still
            // removes it: a genuine leftover is old on the next pass, and a write in progress is
            // seconds old and survives.
            guard let modified = handle.modified(name) else { continue }
            let observed = now()
            let arrived = modified > observed ? Date.distantPast : modified
            guard observed.timeIntervalSince(arrived) > Self.staleAfter else { continue }
            handle.remove(name)
        }
    }
}
