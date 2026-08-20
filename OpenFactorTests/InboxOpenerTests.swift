import Foundation
import Testing

@testable import OpenFactor
@testable import OpenFactorCore

/// What the app does with something the system hands it.
///
/// The important cases are the refusals. This code runs on input the person did not choose and
/// often did not see: a URL from another process, or a link that arrived somehow. Anything it
/// accepts goes to the parser, so what it turns away matters more than what it lets through.
@Suite("Opening what arrived")
struct InboxOpenerTests {

    private func makeInbox() -> (SharedInbox, URL) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        return (SharedInbox(container: { container }), container)
    }

    /// The two standard schemes, which is how a code scanned by the Camera app or found in
    /// Photos reaches this app at all.
    @Test(
        "A setup or transfer code arrives verbatim",
        arguments: [
            "otpauth://totp/Example:someone@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=Example",
            "otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8",
        ])
    func codesArriveWhole(raw: String) {
        #expect(InboxOpener.arrival(from: URL(string: raw)!) == .code(raw))
    }

    /// Case is not the sender's to decide. iOS lowercases schemes, but a URL built by hand
    /// elsewhere may not, and refusing one on that basis would be a confusing failure.
    @Test("The scheme comparison ignores case")
    func schemeIsCaseInsensitive() {
        let raw = "OTPAUTH://totp/Example?secret=GEZDGNBVGY3TQOJQ"
        #expect(InboxOpener.arrival(from: URL(string: raw)!) == .code(raw))
    }

    /// **Everything else is refused**, which matters more than what is accepted. A declared
    /// scheme is an entry point every app on the device can use, so the accepted set is exactly
    /// the two schemes declared plus file URLs. OpenFactor's own scheme was removed once nothing
    /// could produce it, and must not creep back in through this door.
    @Test(
        "Any other URL is refused",
        arguments: [
            "openfactor://inbox?item=6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F",
            "openfactor://inbox",
            "https://example.com/inbox",
            "otpauth-fake://totp/Example?secret=GEZDGNBVGY3TQOJQ",
            "javascript:alert(1)",
        ])
    func refusesEverythingElse(raw: String) {
        #expect(InboxOpener.arrival(from: URL(string: raw)!) == nil)
    }

    /// The ceiling a QR code used to provide for free. Before the scheme existed, a payload
    /// could only come from a camera frame or a decoded image, both limited by what a QR can
    /// physically hold. A URL has no such limit and another app supplies it.
    @Test("A payload longer than any real QR code could hold is refused")
    func oversizedPayloadIsRefused() {
        let padding = String(repeating: "A", count: InboxOpener.longestCode)
        let raw = "otpauth-migration://offline?data=\(padding)"
        #expect(raw.utf8.count > InboxOpener.longestCode)
        #expect(InboxOpener.arrival(from: URL(string: raw)!) == nil)
    }

    /// And the bound must not refuse a real one. A migration QR carrying several accounts is
    /// large, and turning those away would break the case the scheme exists for.
    @Test("A payload the size of a full QR code is accepted")
    func realisticPayloadIsAccepted() {
        // 4,296 characters is a QR code's alphanumeric capacity, so nothing scannable exceeds it.
        let padding = String(repeating: "A", count: 4_296)
        let raw = "otpauth-migration://offline?data=\(padding)"
        #expect(InboxOpener.arrival(from: URL(string: raw)!) == .code(raw))
    }

    /// Handed on verbatim rather than rebuilt. A round trip through `URLComponents` can change
    /// percent encoding, and the secret is inside those query items.
    @Test("The payload is not rewritten on the way through")
    func payloadIsVerbatim() {
        let raw = "otpauth://totp/Example%20Inc:a%2Bb@example.com?secret=GEZDGNBVGY3TQOJQ"
        guard case let .code(payload) = InboxOpener.arrival(from: URL(string: raw)!) else {
            Issue.record("expected a code")
            return
        }
        #expect(payload == raw)
    }

    /// A file from Files or Mail is handed on as a file, because the importer reads it itself
    /// with security scoped access. It must not be confused with an inbox item.
    @Test("A file URL arrives as a file")
    func fileArrivesAsAFile() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let file = URL(fileURLWithPath: "/tmp/example.openfactor")
        #expect(InboxOpener.arrival(from: file) == .file(file))
    }
}

/// Collecting at launch, which is the only route that works: a share extension cannot open its
/// containing app, measured on a phone rather than assumed.
@Suite("Collecting at launch")
struct InboxCollectionTests {

    private func makeInbox() -> (SharedInbox, URL) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString)")
        return (SharedInbox(container: { container }), container)
    }

    @Test("An empty inbox produces nothing")
    func nothingWaiting() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(InboxOpener.collect(from: inbox) == nil)
    }

    /// **The medium a round four review walked out, and the fix for an earlier one is what made
    /// it reachable.** The sweep used to run in a `defer`, so it ran on the failure path too. A
    /// sibling plants one item `take` will refuse, a named pipe or a file over the limit, with a
    /// newer timestamp so it sorts first; the take fails, nothing is presented, and the sweep
    /// deletes every genuine share beside it. Before the read was bounded, the pipe hung on the
    /// main actor and the `defer` never ran, so closing the hang opened this.
    ///
    /// Move the supersede back into a `defer` and this goes red.
    @Test("A poison item that cannot be taken does not destroy what is beside it")
    func afailedTakeLeavesTheRest() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let genuine = try inbox.write(Data("somebody's transfer QR".utf8))
        let directory = container.appendingPathComponent(SharedInbox.directoryName)
        // Aged so the poison written next sorts ahead of it. A future stamp would not do it:
        // `pending` refuses one of those and sorts it last, deliberately.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-5)],
            ofItemAtPath: directory.appendingPathComponent(genuine.uuidString).path)

        let poison = directory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0, count: ImportLimits.policyBytes + 1).write(to: poison)

        #expect(InboxOpener.collect(from: inbox) == nil, "the poison sorts first and is refused")
        #expect(
            inbox.pending().map(\.id) == [genuine],
            "and the share somebody actually made is still there")
        #expect(
            !FileManager.default.fileExists(atPath: poison.path),
            "while the item that could not be taken is gone")
    }

    /// **The consequence the core test cannot show.** A directory with a UUID name sorts newest,
    /// so it is what a collection reaches for; the take refuses it, the collection returns
    /// nothing, and the genuine share behind it is never presented. Unlike a poison file, the
    /// directory cannot be removed either, so refreshing its timestamp hides the share again on
    /// every attempt.
    @Test("A planted directory does not hide a genuine share")
    func aPlantedDirectoryDoesNotHideSomethingReal() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = try inbox.write(Data("somebody's transfer QR".utf8))
        try FileManager.default.createDirectory(
            at: container.appendingPathComponent(SharedInbox.directoryName)
                .appendingPathComponent(UUID().uuidString),
            withIntermediateDirectories: true)

        #expect(
            InboxOpener.collect(from: inbox) == .image(Data("somebody's transfer QR".utf8)),
            "the share is presented rather than shadowed by something that is not a file")
    }

    /// The other half: what a successful collection supersedes is what it read, not whatever the
    /// directory holds by the time the deletion runs.
    @Test("Collecting leaves an item that arrived while it was deciding")
    func collectingLeavesALaterArrival() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = try inbox.write(Data("older, and superseded".utf8))
        let newest = try inbox.write(Data("the one collected".utf8))
        #expect(InboxOpener.collect(from: inbox) == .image(Data("the one collected".utf8)))
        _ = newest

        let arrivedDuring = try inbox.write(Data("shared a moment later".utf8))
        #expect(inbox.pending().map(\.id) == [arrivedDuring])
    }

    @Test("A fresh item is collected")
    func freshIsCollected() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = try inbox.write(Data("a QR code".utf8))
        #expect(InboxOpener.collect(from: inbox) == .image(Data("a QR code".utf8)))
    }

    /// The property the whole container argument rests on: nothing accumulates. Collecting once
    /// must leave the directory empty, including anything it chose not to present.
    @Test("Collecting empties the inbox, including what it did not use")
    func collectingSweepsTheRest() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        for _ in 0..<3 { _ = try inbox.write(Data("a QR code".utf8)) }
        #expect(InboxOpener.collect(from: inbox) != nil)
        #expect(inbox.pending().isEmpty)
    }

    @Test("Collecting twice does not hand over the same image again")
    func collectingIsSingleUse() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = try inbox.write(Data("a QR code".utf8))
        #expect(InboxOpener.collect(from: inbox) != nil)
        #expect(InboxOpener.collect(from: inbox) == nil)
    }

    /// A stale item is swept unread rather than presented, so opening the app for a code does
    /// not drop you into an import sheet for something shared last week.
    @Test("A stale item is discarded rather than shown")
    func staleIsDiscarded() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        let url = container
            .appendingPathComponent(SharedInbox.directoryName)
            .appendingPathComponent(id.uuidString)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-SharedInbox.freshness - 60)],
            ofItemAtPath: url.path)

        #expect(InboxOpener.collect(from: inbox) == nil)
        #expect(inbox.pending().isEmpty, "and it must not be left behind")
    }
}
