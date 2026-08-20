import Foundation

/// The inbox directory, opened once and then operated on through that descriptor.
///
/// ## Why a descriptor rather than a path
///
/// The inbox lives in an App Group, and `docs/VAULT.md` says plainly that a group is not a
/// confidentiality boundary: a sibling of the same team can be authorized into it. Everything
/// this app does there has to survive that sibling being hostile.
///
/// **A path is resolved afresh on every call, and every component of it is a chance to be
/// redirected.** `O_NOFOLLOW` protects the last component only, so a reader that opens
/// `<group>/Inbox/<name>` by path is protected against `<name>` being a link and not against
/// `Inbox` being one. Replace the directory with a link and a sweep that enumerates by path and
/// deletes by path is deleting somebody else's tree, recursively, on the app's own authority.
///
/// Opening the directory once with `O_DIRECTORY | O_NOFOLLOW` and doing the rest relative to that
/// descriptor closes it. The descriptor names the directory this app opened, and keeps naming it
/// even if the path is repointed a moment later.
///
/// **Deletion here is `unlinkat` without `AT_REMOVEDIR`, so it removes files and never a tree.**
/// That is the second half of the same answer: nothing this type does can recurse, whatever it is
/// pointed at.
///
/// ## What it does not cover
///
/// The extension's write still goes through `FileManager` and `Data.write`, which are path based.
/// `SharedInbox.write` opens one of these first and refuses if that fails, so a directory already
/// replaced is caught, but a substitution made between that check and the write is not. Writing
/// an image the owner just shared into a directory a hostile sibling controls costs the owner an
/// image that sibling could already read from the real one, which is why the sweep and the read
/// were done first.
struct InboxDirectory: ~Copyable {

    private let descriptor: Int32

    /// Opens the directory, or fails because it is missing, is not a directory, or is a link.
    init?(at url: URL) {
        let opened = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard opened >= 0 else { return nil }
        descriptor = opened
    }

    deinit { close(descriptor) }

    /// Every name in the directory, excluding `.` and `..`.
    ///
    /// `fdopendir` takes ownership of the descriptor it is given and `closedir` closes it, so it
    /// is handed a duplicate and this type keeps its own.
    func names() -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { return [] }
        guard let stream = fdopendir(duplicate) else {
            close(duplicate)
            return []
        }
        defer { closedir(stream) }

        var found: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            found.append(name)
        }
        return found
    }

    /// When a name was last written, without following it if it is a link.
    ///
    /// **Read at the moment the caller needs it rather than once for a whole pass.** A sweep that
    /// takes one timestamp and then judges every file against it is judging later files by an
    /// earlier clock, which is how a file that arrives during a sweep gets deleted for being old.
    func modified(_ name: String) -> Date? {
        var info = stat()
        guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        // **Nanoseconds included.** Whole seconds are not enough resolution here: two items
        // written in the same second would sort arbitrarily, and the newest one is the one the
        // app presents.
        let stamp = info.st_mtimespec
        return Date(
            timeIntervalSince1970: TimeInterval(stamp.tv_sec)
                + TimeInterval(stamp.tv_nsec) / 1_000_000_000)
    }

    /// Removes one name. Never a directory, and never recursively.
    func remove(_ name: String) {
        unlinkat(descriptor, name, 0)
    }

    /// Reads one name, bounded, through the same primitive every other read in this app uses.
    func read(_ name: String, limit: Int) throws(BoundedFile.ReadError) -> Data {
        let opened = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard opened >= 0 else {
            switch errno {
            case ENOENT: throw .missing
            case ELOOP: throw .notARegularFile
            default: throw .unreadable
            }
        }
        defer { close(opened) }
        return try BoundedFile.read(descriptor: opened, limit: limit)
    }
}
