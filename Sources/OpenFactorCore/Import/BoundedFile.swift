import Foundation

/// Reads a file with a limit that cannot be skipped, and refuses what would hang.
///
/// ## Why one primitive rather than four
///
/// A bound on an untrusted file is easy to write four different ways and hard to write right, and
/// this project had four: read then measure, measure then read, stat then read, and open then
/// read. Only the last is sound, and the difference is not visible at a call site.
///
/// **Measuring first is the mistake with two shapes.** The size and the read are separate calls,
/// so whoever supplied the file can change it in the gap and the bound describes a file that no
/// longer exists; and when the file system gives no size at all, a check written that way skips
/// itself. Reading first is the same mistake with the allocation already made.
///
/// One open and one bounded read leaves no gap for either. There is one implementation, so a
/// mistake found here is fixed for every caller at once, and a caller that wants a different
/// bound passes a different number rather than writing a fifth shape.
///
/// ## What it refuses, and why each one
///
/// - **Not a regular file.** A pipe blocks, a directory is not readable as bytes, and a device
///   node is neither. Checked with `fstat` on the descriptor that will be read, not on the path,
///   so the answer cannot go stale.
/// - **A symbolic link in the last path component**, via `O_NOFOLLOW`, because a link is a way of
///   naming a file this app did not intend to open. `O_NOFOLLOW` covers that component and no
///   other: a caller whose *directory* can be substituted needs a descriptor for it, which is
///   what `read(descriptor:limit:)` is for.
/// - **One byte past the limit**, which is how the limit is enforced: it reads `limit + 1` and
///   refuses if that many arrive. Nothing measures the file first, so nothing can be wrong.
///
/// **What it does not promise.** A file already open can still be changed underneath the read by
/// whoever can write it. The bound holds regardless, because the bound is on how much is taken,
/// not on what the file was.
public enum BoundedFile {

    public enum ReadError: Error, Equatable, Sendable {
        /// There is no file at that path. Distinct from the rest so a caller can treat absence as
        /// an ordinary state rather than a fault, which the vault key store does.
        case missing
        /// The file exists and could not be opened or read.
        case unreadable
        /// A pipe, a directory, a socket, a device, or a symbolic link.
        case notARegularFile
        /// More than the limit allows.
        ///
        /// One byte past the limit is read, because that is how the limit is detected, and then
        /// dropped. Nothing beyond it is ever held.
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
        return try read(descriptor: descriptor, limit: limit)
    }

    /// The same bounded read, given a descriptor somebody else opened.
    ///
    /// **Exists so the inbox can open relative to a directory it has already verified.** Opening
    /// by pathname resolves every component afresh, and only the last one is protected by
    /// `O_NOFOLLOW`; a caller that has a descriptor for the containing directory can do better,
    /// and should not have to carry a second copy of this loop to do it.
    ///
    /// The descriptor stays the caller's to close.
    static func read(descriptor: Int32, limit: Int) throws(ReadError) -> Data {
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
