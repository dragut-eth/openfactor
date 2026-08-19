import Foundation

/// How large a file this app will read, and which bound applies to which format.
///
/// ## The three failure sequences this exists to prevent
///
/// **One: the bound ran after the allocation it claimed to prevent.** `ImportViewModel.read(_ url:)`
/// called `Data(contentsOf:)` and only then looked at `data.count`. A four hundred megabyte
/// attachment opened into this app was a four hundred megabyte allocation, which on a phone is a
/// termination rather than a "too large" message. The comment above the check said "bounded before
/// anything parses it", which was true about parsing and false about the copy.
///
/// **Two: the same number quietly retired the format's frozen ceiling.** `BACKUP_FORMAT.md` permits
/// eight mebibytes of *decoded ciphertext*, which is about 11.2 million base64 characters plus a
/// JSON wrapper. Refusing every file over eight mebibytes therefore refused conforming version 1
/// archives, and refused them before the passphrase screen, so their owner could not tell them
/// apart from rubbish. Gate A3 found that exact mistake inside `BackupArchive.read` and it was
/// fixed there; this was the same defect one layer up, where no test was looking.
///
/// **Three: the writer could produce what the reader must refuse.** Nothing stopped an export
/// exceeding the ceiling, so this app could write an archive that this app would not read back.
///
/// ## The rule
///
/// A file is worth loading if it could be *any* accepted format, which means the largest ceiling of
/// them all. Once loaded and recognised, each format is held to its own bound: an OpenFactor
/// archive to the frozen ceiling, and everything else to a policy bound this project chose for
/// itself and may change without breaking any promise.
public enum ImportLimits {

    /// What any format other than an OpenFactor archive may occupy.
    ///
    /// **A policy, not a specification.** Aegis exports and labelled text never claimed a ceiling,
    /// so this number is this project's choice about how much memory to spend on somebody else's
    /// file format, and changing it breaks no promise to anybody.
    public static let policyBytes = 8 * 1024 * 1024

    /// The largest file worth copying into memory at all, whatever it turns out to be.
    ///
    /// The frozen ceiling, because an OpenFactor archive is the biggest thing this app accepts and
    /// a file cannot be recognised before it is read.
    public static let largestAcceptableBytes = BackupArchive.maximumFileBytes

    /// Whether a file of this size on disk is worth reading.
    ///
    /// Asked of the file system before the copy, which is the whole point: the answer must not
    /// require the allocation it is deciding about.
    public static func isWorthLoading(fileSize: Int) -> Bool {
        fileSize <= largestAcceptableBytes
    }

    /// Whether bytes already in memory are within the bound for what they turned out to be.
    ///
    /// - Parameter isOpenFactorArchive: the format decides the bound. An archive is held to the
    ///   frozen ceiling and nothing else, so a conforming archive is never refused by a number
    ///   this project invented.
    public static func isWithinBound(_ count: Int, isOpenFactorArchive: Bool) -> Bool {
        count <= (isOpenFactorArchive ? largestAcceptableBytes : policyBytes)
    }
}
