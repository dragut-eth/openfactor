import Foundation
import Testing

@testable import OpenFactorCore

/// The inbox a share extension writes to and the app takes from.
///
/// The tests that matter here are the ones about **removal**, not the round trip. What lands in
/// this directory is a transfer QR, which is every secret its owner has in one image, and the
/// entire argument for the inbox being acceptable rests on it living for seconds. A round trip
/// that left the file behind would pass a naive suite and be the whole bug.
///
/// **What these tests cannot see, stated first.** Nothing here proves the file's protection class
/// is applied, and there is no portable way to check it. A test asserting the attribute was
/// written twice and was wrong both times: macOS reports `NSFileProtectionComplete` for a file it
/// does not protect, and the iOS simulator reports nothing for one it writes with the option set.
/// Either assertion would pass on one platform, fail on the other, and prove nothing on either.
///
/// So the option is asserted by reading `SharedInbox.write`, and the class itself belongs on the
/// list of things measured on hardware, where the vault key's was in gate E6.
@Suite("Shared inbox")
struct SharedInboxTests {

    private func makeInbox() -> (SharedInbox, URL) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        return (SharedInbox(container: { container }), container)
    }

    private func names(in container: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: container.appendingPathComponent(SharedInbox.directoryName).path)) ?? []
    }

    @Test("What the extension writes is what the app takes")
    func roundTrips() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        #expect(try inbox.take(id) == Data("a QR code".utf8))
    }

    /// The property the whole design rests on.
    @Test("Taking removes the file")
    func takingRemoves() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        #expect(names(in: container).count == 1)

        _ = try inbox.take(id)
        #expect(names(in: container).isEmpty)
    }

    /// An import that fails, is cancelled, or crashes must not leave the image behind. The
    /// removal is in a `defer` for this reason, and this is what would catch it moving.
    @Test("Taking removes the file even when the caller throws it away")
    func takingRemovesRegardless() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        _ = try? inbox.take(id)
        #expect(names(in: container).isEmpty)

        // And a second take finds nothing rather than the same secret again.
        #expect(throws: SharedInbox.InboxError.notFound) { _ = try inbox.take(id) }
    }

    /// The case `take` cannot cover: the app never opened, or died between the write and the
    /// read. Without this the image stays until the container is deleted.
    @Test("Superseding removes every item it was given")
    func sweepRemovesWhatItIsGiven() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        var written: [UUID] = []
        for _ in 0..<4 { written.append(try inbox.write(Data("a QR code".utf8))) }
        #expect(names(in: container).count == 4)

        inbox.sweep(written)
        #expect(names(in: container).isEmpty)
    }

    /// **The finding this signature exists for.** Superseding used to empty the directory, so an
    /// item written between the caller reading the inbox and the caller deleting it was destroyed
    /// for being too new to have been part of the decision. Revert `sweep` to a directory listing
    /// and this goes red.
    @Test("Superseding leaves what arrived after the caller looked")
    func sweepLeavesWhatArrivedLater() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let seen = try inbox.write(Data("the one the app read".utf8))
        let snapshot = inbox.pending().map(\.id)
        let arrivedDuring = try inbox.write(Data("shared a moment later".utf8))

        inbox.sweep(snapshot)

        #expect(inbox.pending().map(\.id) == [arrivedDuring])
        #expect(!names(in: container).contains(seen.uuidString))
    }

    /// **The inbox is reached through a descriptor, not a path, and this is why.** A group is not
    /// a confidentiality boundary. A sibling that removes `Inbox` and puts a symbolic link there
    /// redirects everything resolved by name, and a sweep that enumerates by path and deletes by
    /// path would then be deleting somebody else's tree on this app's authority, recursively.
    ///
    /// `O_DIRECTORY | O_NOFOLLOW` refuses to open it at all, so every operation declines rather
    /// than following it. Drop `O_NOFOLLOW` from `InboxDirectory` and the last expectation here
    /// goes red.
    @Test("A substituted inbox directory is refused rather than followed")
    func aSymlinkedDirectoryIsRefused() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let elsewhere = container.appendingPathComponent("somebody-elses")
        try FileManager.default.createDirectory(
            at: elsewhere, withIntermediateDirectories: true)
        let theirs = elsewhere.appendingPathComponent("do-not-delete-this")
        try Data("not ours to touch".utf8).write(to: theirs)

        let inboxPath = container.appendingPathComponent(SharedInbox.directoryName)
        try FileManager.default.createDirectory(
            at: container, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: inboxPath, withDestinationURL: elsewhere)

        #expect(inbox.pending().isEmpty, "nothing is read through it")
        #expect(throws: (any Error).self) { _ = try inbox.write(Data("a QR code".utf8)) }
        inbox.sweepStale(now: { Date().addingTimeInterval(SharedInbox.staleAfter + 1) })
        inbox.sweep([UUID()])

        #expect(
            FileManager.default.fileExists(atPath: theirs.path),
            "and nothing beyond the link was removed")
    }

    /// **A name is not enough to make something an item.** `pending` admitted any entry whose
    /// name parsed as a UUID, without asking whether it was a file. A sibling can create a
    /// directory with a canonical UUID name: it is then offered as the thing to collect, `take`
    /// opens it, the bounded read correctly refuses it as not a regular file, and the removal
    /// that follows is `unlinkat` without `AT_REMOVEDIR`, which correctly refuses directories.
    /// The POSIX behaviour is right at every step and the candidate should never have existed.
    ///
    /// Drop the regular-file requirement from `pending` and this goes red.
    @Test("A directory with a UUID name is never offered as an item")
    func aDirectoryIsNotAnItem() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let mine = try inbox.write(Data("a genuine share".utf8))
        // Created after the share, so it carries the newer timestamp and would sort first.
        try FileManager.default.createDirectory(
            at: container.appendingPathComponent(SharedInbox.directoryName)
                .appendingPathComponent(UUID().uuidString),
            withIntermediateDirectories: true)

        #expect(inbox.pending().map(\.id) == [mine], "only the file is an item")
    }

    /// **The entry that was read and the entry that is acted on must be the same one.** `pending`
    /// turned a name into a `UUID` and threw the spelling away, and `take` and `sweep` then rebuilt
    /// the path from `id.uuidString`, which is canonical uppercase. On a case-sensitive volume
    /// those are two different names: the item chosen on one entry's timestamp is read and deleted
    /// at another. Nothing this app writes is ever lowercase, so requiring the exact spelling can
    /// only ever turn away a name somebody else wrote.
    ///
    /// Remove the spelling check from `pending` and this goes red.
    @Test("A name that is not the canonical spelling is not an item")
    func onlyTheCanonicalSpellingIsAnItem() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let mine = try inbox.write(Data("a genuine share".utf8))

        let directory = container.appendingPathComponent(SharedInbox.directoryName)
        let lowercased = UUID().uuidString.lowercased()
        try Data("planted under a spelling this app never writes".utf8)
            .write(to: directory.appendingPathComponent(lowercased))

        #expect(
            inbox.pending().map(\.id) == [mine],
            "only the entry whose name this app would rebuild exactly is an item")
    }

    @Test("Sweeping an inbox that was never used is not an error")
    func sweepIsSafeWhenEmpty() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(throws: Never.self) { inbox.sweep([UUID()]) }
    }

    /// Names must carry nothing. A URL can be logged, can appear in handoff, and can end up in a
    /// diagnostic bundle, so the only thing in it is an identifier that says nothing.
    @Test("Two writes of identical bytes get different names")
    func namesRevealNothing() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let first = try inbox.write(Data("same".utf8))
        let second = try inbox.write(Data("same".utf8))
        #expect(first != second)
    }

    @Test("A missing app group is an error rather than a crash")
    func noContainerIsHandled() {
        let inbox = SharedInbox(container: { nil })

        #expect(throws: SharedInbox.InboxError.noContainer) { _ = try inbox.write(Data()) }
        #expect(throws: SharedInbox.InboxError.notFound) { _ = try inbox.take(UUID()) }
        #expect(throws: Never.self) { inbox.sweep([UUID()]) }
    }

}

/// Collecting at launch, which is how the app gets an item at all: a share extension is not
/// permitted to open its containing app, so nothing arrives by URL.
@Suite("Collecting from the inbox")
struct SharedInboxCollectionTests {

    private func makeInbox() -> (SharedInbox, URL) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        return (SharedInbox(container: { container }), container)
    }

    @Test("Nothing waiting is an empty list rather than an error")
    func emptyInbox() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(inbox.pending().isEmpty)
    }

    @Test("Reading what is waiting does not consume it")
    func pendingDoesNotConsume() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        #expect(inbox.pending().map(\.id) == [id])
        #expect(inbox.pending().map(\.id) == [id])
        #expect(try inbox.take(id) == Data("a QR code".utf8))
        #expect(inbox.pending().isEmpty)
    }

    /// Newest first, because somebody who shared twice meant the second one.
    @Test("Items come back newest first")
    func newestFirst() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let first = try inbox.write(Data("one".utf8))
        Thread.sleep(forTimeInterval: 1.1)
        let second = try inbox.write(Data("two".utf8))

        #expect(inbox.pending().map(\.id) == [second, first])
    }

    /// The window exists so the app does not open into an import sheet for something shared days
    /// ago. This asserts the value is a real one rather than accidentally zero or enormous.
    @Test("The freshness window is minutes, not seconds and not days")
    func freshnessIsSensible() {
        #expect(SharedInbox.freshness >= 60)
        #expect(SharedInbox.freshness <= 60 * 60)
    }

    @Test("An item carries when it arrived")
    func itemsCarryTheirAge() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = try inbox.write(Data("a QR code".utf8))
        let item = try #require(inbox.pending().first)
        #expect(abs(item.arrived.timeIntervalSinceNow) < 5)
    }

    // MARK: - Gate A4, scope 4

    /// **All three engines found the sweep unreachable in the case it exists for.** The only
    /// sweep sat inside the collection path, which refuses to run until the scene is active, the
    /// lock is open, the vault is open, and no arrival is pending. An image shared to a locked
    /// phone that was never unlocked again stayed in a shared container.
    @Test("A launch sweep removes what nobody came for")
    func staleItemsAreSwept() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("a transfer QR nobody collected".utf8))
        #expect(inbox.pending().count == 1)

        inbox.sweepStale(now: { Date().addingTimeInterval(SharedInbox.staleAfter + 1) })
        #expect(inbox.pending().isEmpty)
        #expect(throws: (any Error).self) { try inbox.take(id) }
    }

    /// And the reason the launch sweep is not simply `sweep()`: it must not eat the item somebody
    /// shared a second ago, which is the whole feature.
    @Test("A launch sweep leaves what somebody just shared")
    func freshItemsSurviveTheSweep() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try inbox.write(Data("shared a moment ago".utf8))

        inbox.sweepStale()
        #expect(inbox.pending().count == 1, "the ordinary path is untouched")
    }

    /// **A stamp in the future is evidence about the writer, not about the time.**
    ///
    /// The first fix clamped it to `now`, and round two rejected that in all three reviews: the
    /// value is recomputed on every read, so the item reported an age of zero forever. It sorted
    /// first, stayed fresh, and became the one item the launch sweep could never remove. This
    /// test asserts the two properties that clamp version passed while failing.
    @Test("A future timestamp sorts last and sweeps immediately")
    func futureTimestampsAreRefused() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let genuine = try inbox.write(Data("what somebody actually shared".utf8))
        let planted = try inbox.write(Data("planted".utf8))

        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(planted.uuidString)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(86_400)], ofItemAtPath: url.path)

        // The genuine share is the one offered, not the one claiming to be from tomorrow.
        let newest = try #require(inbox.pending().first)
        #expect(newest.id == genuine)

        // And the plant is stale on sight rather than immortal.
        inbox.sweepStale()
        #expect(inbox.pending().map(\.id) == [genuine], "the plant is gone, the share is not")
    }

    /// **One idea, one constant.** These were five and ten minutes, so an item aged between them
    /// was worth presenting by one rule and deleted unread by the other.
    @Test("An item stops being presentable exactly when it becomes sweepable")
    func oneThresholdRatherThanTwo() {
        #expect(SharedInbox.staleAfter == SharedInbox.freshness)
    }

    /// A name this app did not write is not something to leave in a shared container, but it is
    /// judged by age like everything else.
    @Test("A file the app did not write is swept once it is stale")
    func unknownNamesAreSweptWhenStale() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let mine = try inbox.write(Data("mine".utf8))
        let theirs = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent("not-a-uuid")
        try Data("planted under a name the sweep could not see".utf8).write(to: theirs)

        inbox.sweepStale(now: { Date().addingTimeInterval(SharedInbox.staleAfter + 1) })

        #expect(!FileManager.default.fileExists(atPath: theirs.path))
        #expect(inbox.pending().map(\.id) == [], "and everything else stale went with it")
        _ = mine
    }

    /// **Deleting a foreign name on sight collides with the atomic write it shares the directory
    /// with.** `Data.write(options: .atomic)` puts a temporary file alongside the real one and
    /// renames it, and that temporary name is exactly a name this app did not write. Age is what
    /// separates a genuine leftover from a write still in progress. Remove the age gate on the
    /// unknown branch and this goes red.
    @Test("A file the app did not write is left alone while it is fresh")
    func unknownNamesSurviveWhileFresh() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try inbox.write(Data("mine".utf8))
        let inProgress = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent("openfactor-write-in-progress")
        try Data("half of an atomic write".utf8).write(to: inProgress)

        inbox.sweepStale()

        #expect(FileManager.default.fileExists(atPath: inProgress.path))
    }

    /// **The clock is read after the file, not before the directory.** A pass that samples the
    /// clock at entry and then judges each entry against it is judging a file written during the
    /// pass against a moment before that file existed: its honest timestamp is later than the
    /// sample, which is the same shape as a hostile plant stamped in 2090, and the pass cannot
    /// tell them apart. It deletes the share somebody made a second ago for being from the future.
    ///
    /// **The clock is the seam, because the clock is what makes the race deterministic.** Reading
    /// it is the first thing a pass that samples early does, and it happens after the listing in
    /// a pass that samples late. So a clock that writes a share the first time it is read lands
    /// that share squarely inside the window. Sample `now()` once at the top of `sweepStale` and
    /// this goes red: the share is listed, its stamp is later than that sample, and it is removed.
    @Test("A share that lands during a sweep is not deleted for being from the future")
    func aShareLandingDuringASweepSurvives() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Something to iterate over, so the pass has an entry whose clock reading can land the
        // share below.
        let alreadyHere = try inbox.write(Data("shared earlier".utf8))

        // The reading is taken **before** the share is written, which is the race: the pass has
        // its clock, and the extension lands a file a moment later.
        let landed = LockedBox<UUID>()
        inbox.sweepStale(now: {
            let reading = Date()
            if landed.value == nil { landed.value = try? inbox.write(Data("landed mid-pass".utf8)) }
            return reading
        })

        let arrived = try #require(landed.value, "the clock was read, so the share was written")
        #expect(
            inbox.pending().map(\.id).sorted() == [alreadyHere, arrived].sorted(),
            "the share that landed during the sweep is still here")
    }

    /// The same ordering in `pending`, where the consequence is different and no less bad: a share
    /// that lands during the listing is stamped `.distantPast`, sorts last, and is then inside the
    /// identifier set a collection supersedes. Last wins, inverted.
    @Test("A share that lands during a listing is never recorded as ancient")
    func aShareLandingDuringAListingIsNotAncient() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try inbox.write(Data("shared earlier".utf8))

        let landed = LockedBox<UUID>()
        let waiting = inbox.pending(now: {
            let reading = Date()
            if landed.value == nil { landed.value = try? inbox.write(Data("landed mid-pass".utf8)) }
            return reading
        })

        #expect(landed.value != nil, "the clock was read, so the share was written")
        #expect(
            waiting.allSatisfy { $0.arrived != .distantPast },
            "nothing a moment old may be recorded as arriving before everything")
    }

    /// **A sweep that reads one clock and then judges every file against it** measures a file
    /// written during the pass against a moment before it existed. Each timestamp is read
    /// immediately before its own removal.
    @Test("An item written during a sweep is judged by its own timestamp")
    func agesAreReadPerFile() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fresh = try inbox.write(Data("just shared".utf8))
        inbox.sweepStale(now: { Date() })

        #expect(inbox.pending().map(\.id) == [fresh])
    }

    /// **The bound cannot be skipped, and there is nothing to race.** The old shape asked for a
    /// size and then called a separate read, so a missing size skipped the check entirely and a
    /// writer sharing the container could swap the file between the two calls.
    @Test("An item with no readable size is still bounded")
    func theBoundCannotBeSkipped() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("small".utf8))
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try Data(repeating: 0, count: ImportLimits.policyBytes + 1).write(to: url)

        #expect(throws: SharedInbox.InboxError.tooLarge) { try inbox.take(id) }
        #expect(inbox.pending().isEmpty)
    }

    /// The inbox holds a QR image of every secret in somebody's authenticator for a few seconds.
    /// A backup taken in those seconds used to carry it away, where nothing sweeps it.
    @Test("The inbox directory is excluded from backups")
    func inboxIsExcludedFromBackups() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try inbox.write(Data("anything".utf8))

        let inboxDirectory = URL(
            fileURLWithPath: directory.appendingPathComponent(SharedInbox.directoryName).path)
        #expect(
            try inboxDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true)
    }

    /// `take` copied whatever was in the container into memory, with the bound, where there was
    /// one, applied afterwards.
    @Test("Taking an item at the limit still works")
    func takingAnOversizedItemRefuses() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("small enough".utf8))
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try Data(repeating: 0, count: ImportLimits.policyBytes + 1).write(to: url)

        #expect(throws: SharedInbox.InboxError.tooLarge) { try inbox.take(id) }
        #expect(inbox.pending().isEmpty, "and it is off the device rather than left for next time")
    }

    /// **The hang, at the call site that faces a container another process can write.** A sibling
    /// can plant a named pipe under a plausible name; opening one blocks until a writer appears,
    /// and this is called on the main actor with the removal in a `defer` that is never reached.
    @Test("A named pipe in the inbox is refused rather than waited on", .timeLimit(.minutes(1)))
    func aPipeIsNotWaitedOn() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try inbox.write(Data("so the directory exists".utf8))

        let planted = UUID()
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(planted.uuidString)
        #expect(url.withUnsafeFileSystemRepresentation { mkfifo($0, 0o600) } == 0, "the premise")

        #expect(throws: (any Error).self) { try inbox.take(planted) }
    }

    /// The inbox carries images, so it is bounded by the image policy rather than by the archive
    /// ceiling, which was four megabytes of slack nothing in this path can use.
    @Test("The inbox is bounded by the image policy")
    func boundedByTheImagePolicy() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("small".utf8))
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try Data(repeating: 0, count: ImportLimits.policyBytes + 1).write(to: url)

        #expect(throws: SharedInbox.InboxError.tooLarge) { try inbox.take(id) }
    }
}

/// Somewhere a `@Sendable` clock closure can record what it did, so a test can land a share
/// inside a pass and then assert on it afterwards.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
