import Foundation
import Testing

@testable import OpenFactorCore

/// Which bound applies to which file, and the three sequences that got this wrong.
///
/// Written before the fix rather than after it, which is the working change gate A4 forced: the
/// two most serious defects this gate has produced both had a passing test that could not see the
/// thing it was written for, because the test was written by whoever wrote the fix and inherited
/// its blind spot.
@Suite("Import limits")
struct ImportLimitsTests {

    /// **The frozen ceiling is the format's, not this project's.** `BACKUP_FORMAT.md` permits
    /// eight mebibytes of decoded ciphertext, which is about 11.2 million base64 characters plus
    /// a wrapper. Refusing an archive at eight mebibytes refused conforming version 1 files, and
    /// refused them before the passphrase screen, so their owner could not tell them apart from
    /// rubbish.
    @Test("A conforming archive above the policy bound is still worth reading")
    func archivesAreHeldToTheFrozenCeiling() {
        let justOverPolicy = ImportLimits.policyBytes + 1

        #expect(ImportLimits.isWithinBound(justOverPolicy, isOpenFactorArchive: true))
        #expect(!ImportLimits.isWithinBound(justOverPolicy, isOpenFactorArchive: false))
    }

    @Test("An archive above the frozen ceiling is refused like anything else")
    func archivesAboveTheCeilingAreRefused() {
        let overCeiling = BackupArchive.maximumFileBytes + 1

        #expect(!ImportLimits.isWithinBound(overCeiling, isOpenFactorArchive: true))
        #expect(ImportLimits.isWithinBound(BackupArchive.maximumFileBytes, isOpenFactorArchive: true))
    }

    /// The bound that decides whether to allocate at all has to be the largest one, because a
    /// file cannot be recognised before it is read.
    @Test("A file is worth loading up to the largest ceiling of any format")
    func worthLoadingUpToTheLargestCeiling() {
        #expect(ImportLimits.isWorthLoading(fileSize: BackupArchive.maximumFileBytes))
        #expect(!ImportLimits.isWorthLoading(fileSize: BackupArchive.maximumFileBytes + 1))

        // The number that used to be the only bound is far below it, which is the defect.
        #expect(ImportLimits.isWorthLoading(fileSize: ImportLimits.policyBytes + 1))
    }

    @Test("The policy bound governs every other format")
    func policyBoundGovernsOtherFormats() {
        #expect(ImportLimits.isWithinBound(ImportLimits.policyBytes, isOpenFactorArchive: false))
        #expect(!ImportLimits.isWithinBound(ImportLimits.policyBytes + 1, isOpenFactorArchive: false))
    }
}
