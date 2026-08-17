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
}
