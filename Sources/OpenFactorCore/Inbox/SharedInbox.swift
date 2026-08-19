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
/// that never opens this app again never runs one. The previous version of this paragraph was
/// mangled by an edit and left a fragment of a deleted sentence in the middle of it, which round
/// three of gate A4 read as the front page of a file nobody could parse.
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
        // item is usually collected within seconds and may sit until the first sweep after
        // `staleAfter`, and a backup taken at any point in that window carries a QR image of
        // every secret in somebody's authenticator into iCloud, where nothing sweeps it. The
        // "lives for seconds" wording here survived two rounds after the lifecycle it described
        // stopped being true. The
        // directory carries the flag rather than each file, and it is marked before the write for
        // the same reason the vault key's staging directory is: a mark applied afterwards leaves
        // a window with nothing to close it.
        //
        // **This used to be `try?` and write anyway**, which a review called failing open: any
        // metadata failure that did not also stop ordinary writes produced a backup-eligible
        // image of every seed, silently. `VaultKeyStore` already refused to write a key it could
        // not exclude, and there was no argument for holding this to a weaker rule.
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
            // **A timestamp after now is refused, not clamped.** The first fix clamped it to
            // `now`, and all three engines of round two walked out why that is inert: the value
            // is recomputed on every read, so a file stamped in 2090 reports an age of zero
            // forever. It still sorted ahead of a genuine share, still passed the freshness
            // test, and could never satisfy the launch sweep, which asks whether the age exceeds
            // a threshold. **The item the sweep exists to remove became the one item it could
            // never remove.**
            //
            // Nothing legitimate writes a stamp in the future, so a stamp in the future is
            // evidence about the writer rather than about the time. It is treated as arriving
            // before everything, which sorts it last and makes it immediately sweepable.
            let stamped = (attributes?[.modificationDate] as? Date) ?? .distantPast
            let arrived = stamped > now ? .distantPast : stamped
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

        // **One open, one bounded read, through the shared primitive.** This file had the right
        // shape first and it still had a hole: it assumed the name identified a regular file. A
        // sibling with access to this container can create a named pipe, and opening one blocks
        // until a writer appears, on the main actor, with the removal below never reached.
        // `BoundedFile` refuses anything that is not a regular file before it reads a byte.
        //
        // Bounded at the image policy, since what the extension writes here is an image. The
        // archive ceiling was four megabytes of slack nothing in this path can use.
        do {
            return try BoundedFile.read(url, limit: ImportLimits.policyBytes)
        } catch .missing {
            throw InboxError.notFound
        } catch .tooLarge {
            throw InboxError.tooLarge
        } catch {
            throw InboxError.notFound
        }
    }

    /// Removes everything, whatever its age.
    ///
    /// **Not called at launch**, which this line claimed for three rounds. `sweepStale` is what
    /// runs when the app comes forward. This one runs after a collection, where taking one item
    /// means the rest were seen and not chosen.
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

    /// How long an item may sit in the inbox before a sweep removes it regardless.
    ///
    /// **The same number as `freshness`, and that is the point.** These were five minutes and ten
    /// minutes, so an item aged between them was worth presenting by one rule and deleted unread
    /// by the other, and which happened depended on whether iOS had kept the process alive. Round
    /// two found the split in all three reviews and the normative lock document sided with
    /// neither. One idea, one constant: an item is removed exactly when it stops being worth
    /// presenting.
    public static let staleAfter = freshness

    /// Removes what nobody is coming for, and leaves what somebody just shared.
    ///
    /// **All three engines found the sweep unreachable in the case it exists for.** `SharedInbox`
    /// said the directory was swept at every launch and `SECURITY.md` said leftovers are swept
    /// when OpenFactor launches, but the only sweep sat inside the collection path, which refuses
    /// to run until the scene is active, the lock is open, the vault is open and no arrival is
    /// pending. An image shared to a locked phone that was never unlocked again stayed there.
    ///
    /// This runs whenever the app comes forward, with none of those conditions. Round two of the
    /// gate found the first version running once per process, which made the threshold a
    /// condition evaluated at launch rather than a deadline.
    public func sweepStale(now: Date = Date()) {
        guard let directory = try? directory() else { return }
        guard
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }

        let ages = Dictionary(
            pending(now: now).map { ($0.id.uuidString, now.timeIntervalSince($0.arrived)) },
            uniquingKeysWith: { first, _ in first })

        for name in names {
            // **A name this app did not write is removed on sight.** The sweep used to consider
            // only names that parse as a UUID, which is every name this app writes and no
            // guarantee about what else is in a shared container. A review pointed out that
            // anything else was the original leftover under a name the sweep could not see.
            guard let age = ages[name] else {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                continue
            }
            guard age > Self.staleAfter else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
