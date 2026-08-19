import Foundation
import Testing

@testable import OpenFactorCore

/// The one primitive four call sites now share, and the four ways the shapes it replaced failed.
@Suite("Bounded file read")
struct BoundedFileTests {

    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bounded-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The bound

    @Test("A file within the limit is read whole")
    func withinTheLimit() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("file")
        let contents = Data(repeating: 7, count: 100)
        try contents.write(to: url)

        #expect(try BoundedFile.read(url, limit: 100) == contents, "exactly at the limit")
        #expect(try BoundedFile.read(url, limit: 1_000) == contents)
    }

    /// One byte past is the whole rule: it reads `limit + 1` and refuses if that many arrive, so
    /// nothing has to measure the file first and nothing can be wrong about the measurement.
    @Test("A file one byte past the limit is refused")
    func pastTheLimit() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("file")
        try Data(repeating: 7, count: 101).write(to: url)

        #expect(throws: BoundedFile.ReadError.tooLarge) { try BoundedFile.read(url, limit: 100) }
    }

    @Test("An empty file is a file")
    func emptyFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("file")
        try Data().write(to: url)

        #expect(try BoundedFile.read(url, limit: 100).isEmpty)
    }

    // MARK: - What is not a file

    /// **The hang.** A sibling with access to a shared container can create a named pipe, and
    /// `FileHandle(forReadingFrom:)`, which this replaced, opens blocking: it waits for a writer
    /// that may never come. This app opens inbox items on the main actor, so that is the
    /// interface stopping, with the removal that would have cleaned up never reached.
    ///
    /// **Two guards, and they do different jobs.** `O_NONBLOCK` is what makes the open return at
    /// all; the `fstat` is what turns "returned but is not a file" into an answer rather than a
    /// read that fails obscurely. Removing the `fstat` alone was measured: this test still fails
    /// rather than hanging, because the flag is doing its half. The blocking version was not run
    /// against a pipe, for the obvious reason.
    @Test("A named pipe is refused rather than waited on", .timeLimit(.minutes(1)))
    func namedPipeDoesNotBlock() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("pipe")
        #expect(url.withUnsafeFileSystemRepresentation { mkfifo($0, 0o600) } == 0, "the premise")

        #expect(throws: BoundedFile.ReadError.notARegularFile) {
            try BoundedFile.read(url, limit: 100)
        }
    }

    @Test("A directory is refused")
    func directoryIsRefused() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BoundedFile.ReadError.notARegularFile) {
            try BoundedFile.read(directory, limit: 100)
        }
    }

    /// A link is a way of naming a file this app did not mean to open.
    @Test("A symbolic link is refused rather than followed")
    func symbolicLinkIsRefused() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let real = directory.appendingPathComponent("real")
        try Data(repeating: 7, count: 10).write(to: real)

        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(throws: BoundedFile.ReadError.notARegularFile) {
            try BoundedFile.read(link, limit: 100)
        }
    }

    /// Absence is its own answer, because the vault key store treats a missing key as the ordinary
    /// state of a fresh install rather than as a fault.
    @Test("A missing file says so, distinctly")
    func missingFile() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BoundedFile.ReadError.missing) {
            try BoundedFile.read(directory.appendingPathComponent("nothing"), limit: 100)
        }
    }
}
