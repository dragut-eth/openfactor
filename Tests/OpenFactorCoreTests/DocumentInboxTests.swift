import Foundation
import Testing

@testable import OpenFactorCore

/// The copies iOS makes when a document is opened into the app, and the rule that only those are
/// ever removed. Audit X3, OF-X3-01.
@Suite("Document inbox")
struct DocumentInboxTests {

    private func makeInbox() throws -> (DocumentInbox, documents: URL, inbox: URL) {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-inbox-\(UUID().uuidString)", isDirectory: true)
        let inbox = documents.appendingPathComponent(DocumentInbox.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return (DocumentInbox(documents: { documents }), documents, inbox)
    }

    private func write(_ name: String, in directory: URL, age: TimeInterval = 0) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("secret".utf8).write(to: url)
        if age > 0 {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        return url
    }

    /// **Ownership is the whole safety property.** Everything below that deletes is gated on it,
    /// and a document picker URL, a sibling directory, or a path that climbs out with `..` must
    /// all be refused, or the fix for keeping secrets becomes a way of destroying somebody's file.
    @Test("Only a file inside the inbox is owned")
    func ownershipIsTheInboxAndNothingElse() throws {
        let (inbox, documents, directory) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: documents) }

        let owned = try write("export.json", in: directory)
        #expect(inbox.owns(owned))

        let sibling = documents.appendingPathComponent("InboxArchive").appendingPathComponent("x")
        #expect(!inbox.owns(sibling), "a prefix that is not a directory boundary")

        let outside = try write("mine.json", in: documents)
        #expect(!inbox.owns(outside), "the person's own document, beside the inbox")

        let climbing = directory.appendingPathComponent("..").appendingPathComponent("mine.json")
        #expect(!inbox.owns(climbing), "a path that starts inside and climbs out")

        #expect(!inbox.owns(URL(string: "https://example.com/export.json")!), "not a file at all")
        #expect(!DocumentInbox(documents: { nil }).owns(owned), "no documents directory, no claim")
    }

    /// **The trusted root must not be movable.** X3's verification round replaced the inbox
    /// directory itself with a link to a sibling, and because both sides of the comparison
    /// followed links, every file in the sibling was owned and deletable. The precondition is
    /// write access inside the private container, out of scope by E4, and the hardening is still
    /// worth one comparison.
    @Test("An inbox that is a link elsewhere owns nothing")
    func redirectedInboxOwnsNothing() throws {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("document-inbox-\(UUID().uuidString)", isDirectory: true)
        let outside = documents.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: documents) }

        try FileManager.default.createSymbolicLink(
            at: documents.appendingPathComponent(DocumentInbox.directoryName),
            withDestinationURL: outside)
        let file = try write("victim.json", in: outside)

        let inbox = DocumentInbox(documents: { documents })
        #expect(!inbox.owns(file), "a file reached through a redirected inbox is not ours")
        inbox.discard(file)
        inbox.sweepAll()
        #expect(FileManager.default.fileExists(atPath: file.path), "and nothing deletes it")
    }

    @Test("Discarding removes an owned copy and leaves everything else alone")
    func discardIsGatedOnOwnership() throws {
        let (inbox, documents, directory) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: documents) }

        let owned = try write("export.json", in: directory)
        let outside = try write("mine.json", in: documents)

        inbox.discard(owned)
        inbox.discard(outside)

        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: outside.path), "never the person's file")
    }

    /// A delivery can land while the app is coming forward, so the launch sweep leaves a fresh
    /// file for the import to read and takes only what has settled.
    @Test("The launch sweep removes settled copies and keeps a fresh one")
    func sweepRespectsAge() throws {
        let (inbox, documents, directory) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: documents) }

        let old = try write("old.json", in: directory, age: DocumentInbox.settledAge + 5)
        let fresh = try write("fresh.json", in: directory)
        let outside = try write("mine.json", in: documents)

        inbox.sweep()

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    /// Erasing is the one moment a recent copy is exactly what must not survive.
    @Test("Sweeping everything after an erase removes fresh copies too")
    func sweepAllRemovesFreshCopies() throws {
        let (inbox, documents, directory) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: documents) }

        let fresh = try write("fresh.json", in: directory)
        inbox.sweepAll()
        #expect(!FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test("A missing inbox directory is nothing to do rather than an error")
    func missingDirectoryIsQuiet() {
        let inbox = DocumentInbox(documents: {
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        })
        inbox.sweep()
        inbox.sweepAll()
    }
}
