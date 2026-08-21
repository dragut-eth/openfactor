import Foundation
import Testing

@testable import OpenFactorCore

/// The inbox directory as a descriptor, tested directly rather than through `SharedInbox`.
///
/// **Nothing exercised this file on its own until now**, which a review named as the residual risk
/// behind its own clearance of it: it verified the primitive by reading, and no test stood behind
/// that reading. One bug here is a bug in every inbox operation at once, so the properties the
/// rest of the inbox rests on belong in assertions rather than in a comment.
@Suite("Inbox directory")
struct InboxDirectoryTests {

    /// `InboxDirectory` is non-copyable, so it cannot be handed to `#require` or compared to
    /// `nil`. Whether it opens is the only thing these cases need.
    private func opens(_ url: URL) -> Bool {
        if InboxDirectory(at: url) != nil { return true }
        return false
    }

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-directory-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Timestamps

    /// **The ordering the whole newest-wins rule depends on.** The first version of `modified`
    /// read `st_mtimespec.tv_sec` and dropped the nanoseconds, so two items written inside the
    /// same second carried identical timestamps and sorted arbitrarily. That was found while the
    /// work was in progress and fixed, and then nothing pinned it: a review pointed out that
    /// reverting to whole seconds would leave the suite green, because the only ordering test
    /// sleeps for more than a second.
    ///
    /// Drop `tv_nsec` from `modified` and this goes red.
    @Test("Two files written milliseconds apart have distinguishable timestamps, in order")
    func subSecondTimestampsAreDistinguishable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("first".utf8).write(to: directory.appendingPathComponent("first"))
        Thread.sleep(forTimeInterval: 0.02)
        try Data("second".utf8).write(to: directory.appendingPathComponent("second"))

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        let firstStamp = handle.modified("first")
        let secondStamp = handle.modified("second")
        let first = try #require(firstStamp)
        let second = try #require(secondStamp)

        #expect(second > first, "the later write must be the later timestamp")
        #expect(
            second.timeIntervalSince(first) < 1,
            "and the gap is under a second, so whole-second resolution would tie them")
    }

    @Test("A name that is not there has no timestamp")
    func missingNameHasNoTimestamp() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        let stamp = handle.modified("nothing-here")
        #expect(stamp == nil)
    }

    // MARK: - Listing

    @Test("Listing excludes the directory's own entries")
    func listingExcludesDotEntries() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("a".utf8).write(to: directory.appendingPathComponent("a"))
        try Data("b".utf8).write(to: directory.appendingPathComponent("b"))

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        let names = Set(handle.names())
        #expect(names == ["a", "b"])
    }

    /// A second listing must see the directory again from the start. `fdopendir` consumes the
    /// descriptor it is handed and `closedir` closes it, so it is given a fresh opening rather
    /// than this type's own; a `dup` would not do, because it shares the file offset and the
    /// second listing would start where the first stopped.
    @Test("Listing twice gives the same answer twice")
    func listingIsRepeatable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("a".utf8).write(to: directory.appendingPathComponent("a"))

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        let first = handle.names()
        let second = handle.names()
        #expect(first == ["a"])
        #expect(second == ["a"], "the descriptor was not consumed by the first listing")
    }

    // MARK: - Removal

    @Test("Removing a file removes it")
    func removingAFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("a")
        try Data("a".utf8).write(to: file)

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        handle.remove("a")

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// **The property everything else in the inbox rests on.** `unlinkat` is called without
    /// `AT_REMOVEDIR`, so it removes a link and never a tree. That is what makes a substituted
    /// directory an accumulation problem rather than an arbitrary-deletion one, and it is the
    /// reason the sweep can be pointed at a hostile name without becoming a weapon.
    ///
    /// Pass `AT_REMOVEDIR`, or reach for `FileManager.removeItem`, and this goes red.
    @Test("Removing never recurses into a directory")
    func removingRefusesADirectory() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let subdirectory = directory.appendingPathComponent("a-directory")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let inside = subdirectory.appendingPathComponent("do-not-delete-this")
        try Data("not ours to touch".utf8).write(to: inside)

        guard let handle = InboxDirectory(at: directory) else {
            Issue.record("the directory did not open")
            return
        }
        handle.remove("a-directory")

        #expect(
            FileManager.default.fileExists(atPath: inside.path),
            "nothing inside a directory may be reached by a removal")
        #expect(
            FileManager.default.fileExists(atPath: subdirectory.path),
            "and the directory itself is left rather than removed")
    }

    // MARK: - Opening

    @Test("A path that is not a directory does not open")
    func aFileDoesNotOpenAsADirectory() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("a")
        try Data("a".utf8).write(to: file)

        #expect(!opens(file))
    }

    /// The capability the whole type exists for: a symbolic link where the directory should be is
    /// refused rather than followed.
    @Test("A symbolic link does not open, whatever it points at")
    func aSymbolicLinkDoesNotOpen() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let elsewhere = directory.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let link = directory.appendingPathComponent("a-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        #expect(!opens(link))
    }

    @Test("A directory that is not there does not open")
    func aMissingDirectoryDoesNotOpen() {
        #expect(
            !opens(
                FileManager.default.temporaryDirectory
                    .appendingPathComponent("nothing-\(UUID().uuidString)")))
    }
}
