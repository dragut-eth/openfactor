import Foundation

/// Reads a file with a limit that cannot be skipped, raced, or hung.
///
/// ## Why this exists, in one sentence per round
///
/// Gate A4 found the same mistake in four places across three scopes, and fixed it four different
/// ways before anybody noticed it was one mistake.
///
/// **Round one:** the import path read the whole file and then measured it, so a four hundred
/// megabyte attachment was a four hundred megabyte allocation before anything refused it.
///
/// **Round two:** the fix asked the file system for a size first, which a review then took apart
/// twice over. The check was skipped entirely when no size came back, and even when it did, the
/// size and the read are two calls with a gap between them: whoever supplied the file can change
/// it in that gap, so the bound describes a file that no longer exists.
///
/// **Round three:** `SharedInbox.take` was rewritten to open once and read through the handle,
/// which all three engines called the correct shape. Two other call sites were left as a stat
/// followed by a read, and one engine filed that while two passed it, on the reasoning that only
/// the shared container faces a hostile writer. **That disagreement is not settled here.** The
/// primitive removes the need to settle it: one open, one bounded read, no window for anybody to
/// be right about.
///
/// And `take`'s rewrite had a hole of its own that a fourth review found: it assumed the path
/// named a regular file. A named pipe in a shared container blocks the reader on open, and this
/// app opens inbox items on the main actor.
///
/// ## What it refuses, and why each one
///
/// - **Not a regular file.** A pipe blocks, a directory is not readable as bytes, and a device
///   node is neither. Checked with `fstat` on the descriptor that will be read, not on the path,
///   so the answer cannot go stale.
/// - **Symbolic links**, via `O_NOFOLLOW`, because a link is a way of naming a file this app did
///   not intend to open.
/// - **One byte past the limit**, which is how the limit is enforced: it reads `limit + 1` and
///   refuses if that many arrive. Nothing measures the file first, so nothing can be wrong.
public enum BoundedFile {

    public enum ReadError: Error, Equatable, Sendable {
        /// There is no file at that path. Distinct from the rest so a caller can treat absence as
        /// an ordinary state rather than a fault, which the vault key store does.
        case missing
        /// The file exists and could not be opened or read.
        case unreadable
        /// A pipe, a directory, a socket, a device, or a symbolic link.
        case notARegularFile
        /// More than the limit allows. The bytes past it were never held.
        case tooLarge
    }

    /// Reads at most `limit` bytes, or refuses.
    public static func read(_ url: URL, limit: Int) throws(ReadError) -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            // **`O_NONBLOCK` so a pipe cannot hold this call**, and `O_NOFOLLOW` so a symbolic
            // link cannot redirect it. Both matter because at least one caller reads a directory
            // another process can write into.
            return open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        }

        guard descriptor >= 0 else {
            switch errno {
            case ENOENT: throw .missing
            // `O_NOFOLLOW` refuses a symbolic link by failing the open with `ELOOP`, which is the
            // same answer as the `fstat` below gives for a pipe or a directory: this path does not
            // name a regular file. Reported as one thing so a caller does not have to know which
            // kind of not-a-file it was.
            case ELOOP: throw .notARegularFile
            default: throw .unreadable
            }
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .unreadable }
        guard info.st_mode & S_IFMT == S_IFREG else { throw .notARegularFile }

        let ceiling = limit + 1
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while data.count < ceiling {
            let wanted = Swift.min(buffer.count, ceiling - data.count)
            let got = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress, wanted)
            }

            if got == 0 { break }
            guard got > 0 else { throw .unreadable }
            data.append(contentsOf: buffer[0..<got])
        }

        guard data.count <= limit else { throw .tooLarge }
        return data
    }
}
