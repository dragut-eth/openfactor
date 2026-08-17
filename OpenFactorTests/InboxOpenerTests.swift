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

    @Test("An inbox link produces the bytes the extension wrote")
    func inboxLinkArrives() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        let url = URL(string: "openfactor://inbox?item=\(id.uuidString)")!

        #expect(InboxOpener.arrival(from: url, inbox: inbox) == .data(Data("a QR code".utf8)))
    }

    /// The lifecycle, asserted from the outside: following the link twice must not hand the same
    /// image over twice, because the first read is supposed to have removed it.
    @Test("The same link cannot be followed twice")
    func linksAreSingleUse() throws {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let id = try inbox.write(Data("a QR code".utf8))
        let url = URL(string: "openfactor://inbox?item=\(id.uuidString)")!

        #expect(InboxOpener.arrival(from: url, inbox: inbox) != nil)
        #expect(InboxOpener.arrival(from: url, inbox: inbox) == nil)
    }

    @Test(
        "A link that is not ours, or not shaped right, is ignored",
        arguments: [
            "openfactor://inbox",
            "openfactor://inbox?item=not-a-uuid",
            "openfactor://inbox?other=x",
            "openfactor://elsewhere?item=6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F",
            "openfactor://inbox?item=6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F",
            "https://example.com/inbox?item=6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F",
        ])
    func refusesRubbish(raw: String) {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        #expect(InboxOpener.arrival(from: URL(string: raw)!, inbox: inbox) == nil)
    }

    /// A file from Files or Mail is handed on as a file, because the importer reads it itself
    /// with security scoped access. It must not be confused with an inbox item.
    @Test("A file URL arrives as a file")
    func fileArrivesAsAFile() {
        let (inbox, container) = makeInbox()
        defer { try? FileManager.default.removeItem(at: container) }

        let file = URL(fileURLWithPath: "/tmp/example.openfactor")
        #expect(InboxOpener.arrival(from: file, inbox: inbox) == .file(file))
    }
}
