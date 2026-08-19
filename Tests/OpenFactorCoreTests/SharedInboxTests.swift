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
    @Test("The sweep removes everything, including items nobody asked for")
    func sweepRemovesEverything() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        for _ in 0..<4 { _ = try inbox.write(Data("a QR code".utf8)) }
        #expect(names(in: container).count == 4)

        inbox.sweep()
        #expect(names(in: container).isEmpty)
    }

    @Test("Sweeping an inbox that was never used is not an error")
    func sweepIsSafeWhenEmpty() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(throws: Never.self) { inbox.sweep() }
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
        #expect(throws: SharedInbox.InboxError.noContainer) { _ = try inbox.take(UUID()) }
        #expect(throws: Never.self) { inbox.sweep() }
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

        inbox.sweepStale(now: Date().addingTimeInterval(SharedInbox.staleAfter + 1))
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

    /// **The timestamp is not this app's.** A modification date in the future made an item sort
    /// ahead of everything and look newer than anything that could have arrived.
    @Test("An item cannot claim it arrived after now")
    func futureTimestampsAreClamped() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("planted".utf8))
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(86_400)], ofItemAtPath: url.path)

        let now = Date()
        let item = try #require(inbox.pending(now: now).first)
        #expect(item.arrived <= now, "clamped to now rather than believed")
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
    @Test("Taking an oversized item refuses and removes it")
    func takingAnOversizedItemRefuses() throws {
        let (inbox, directory) = makeInbox()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = try inbox.write(Data("small enough".utf8))
        let url = directory.appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try Data(repeating: 0, count: ImportLimits.largestAcceptableBytes + 1).write(to: url)

        #expect(throws: SharedInbox.InboxError.tooLarge) { try inbox.take(id) }
        #expect(inbox.pending().isEmpty, "and it is off the device rather than left for next time")
    }
}
