import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The one record that makes recovery on another device possible.
///
/// Every test here uses a deliberately low iteration count, because the work factor has nothing
/// to do with the layout and paying 600,000 iterations per case would make the suite unusable.
/// The real number is asserted once, separately, as a constant.
@Suite("Wrapped vault key")
struct WrappedVaultKeyTests {

    private let passphrase = "YZTR-THFW-WT6E-OXIV-73XD-QCDM"
    private let iterations = 100_000
    private let vaultKey = SymmetricKey(data: Data(repeating: 0x11, count: 32))

    private func wrapped() throws -> Data {
        try WrappedVaultKey.wrap(
            vaultKey: vaultKey, passphrase: passphrase, iterations: iterations)
    }

    // MARK: - Layout

    @Test("The record is exactly the size the page specifies, laid out where it says")
    func layoutIsExact() throws {
        let record = try wrapped()

        #expect(record.count == 100)
        #expect(record.count == WrappedVaultKey.recordSize)
        #expect(record.prefix(4) == Data("OFK1".utf8))

        let storedIterations = record[36..<40].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(storedIterations == UInt32(iterations))
    }

    @Test("Writers use the count the archive uses")
    func writeIterationsMatchTheArchive() {
        #expect(WrappedVaultKey.writeIterations == 600_000)
        #expect(WrappedVaultKey.writeIterations == BackupArchive.writeIterations)
    }

    // MARK: - Round trip

    @Test("The vault key comes back")
    func roundTrips() throws {
        let recovered = try WrappedVaultKey.unwrap(try wrapped(), passphrase: passphrase)

        #expect(
            recovered.withUnsafeBytes { Data($0) } == vaultKey.withUnsafeBytes { Data($0) })
    }

    /// The passphrase is canonicalised, so every way a person hands it back reaches the same
    /// key. This is the same guarantee the archive publishes vectors for, and it matters more
    /// here because there is no second chance: this record is how a new phone recovers.
    @Test(
        "Every form of the passphrase recovers the key",
        arguments: [
            "YZTR-THFW-WT6E-OXIV-73XD-QCDM",
            "yztr-thfw-wt6e-oxiv-73xd-qcdm",
            "YZTR THFW WT6E OXIV 73XD QCDM",
            "YZTRTHFWWT6EOXIV73XDQCDM",
            "\u{FEFF}YZTR-THFW-WT6E-OXIV-73XD-QCDM\n",
        ]
    )
    func acceptsEveryFormOfThePassphrase(input: String) throws {
        let recovered = try WrappedVaultKey.unwrap(try wrapped(), passphrase: input)

        #expect(
            recovered.withUnsafeBytes { Data($0) } == vaultKey.withUnsafeBytes { Data($0) })
    }

    // MARK: - Freshness

    /// The writer mistake the format documents call catastrophic. A passphrase change rewraps,
    /// so this is not a one-off at creation.
    @Test("Every wrap uses a fresh salt and a fresh nonce")
    func everyWrapIsFresh() throws {
        var salts: Set<Data> = []
        var nonces: Set<Data> = []

        for _ in 0..<8 {
            let record = try wrapped()
            salts.insert(record[4..<36])
            nonces.insert(record[40..<52])
        }

        #expect(salts.count == 8)
        #expect(nonces.count == 8)
    }

    // MARK: - What must fail

    @Test("A wrong passphrase is refused as a wrong passphrase")
    func wrongPassphraseFails() throws {
        #expect(throws: WrappedVaultKey.WrapError.wrongPassphrase) {
            try WrappedVaultKey.unwrap(try self.wrapped(), passphrase: "AAAA-BBBB-CCCC-DDDD")
        }
    }

    @Test("Anything that is not a wrapped key is refused as one")
    func rejectsNonRecords() throws {
        let record = try wrapped()

        for bytes in [Data(), Data("OFK1".utf8), record.dropLast(), record + Data([0])] {
            #expect(throws: WrappedVaultKey.WrapError.notAWrappedKey) {
                try WrappedVaultKey.unwrap(bytes, passphrase: self.passphrase)
            }
        }
    }

    /// The salt and the iteration count have to sit outside the seal to derive at all, so they
    /// are bound as additional data instead. A writer altering either is detected.
    @Test("Altering the salt or the iteration count is detected")
    func headerIsBound() throws {
        var withSaltChanged = try wrapped()
        withSaltChanged[10] ^= 0xFF
        #expect(throws: WrappedVaultKey.WrapError.wrongPassphrase) {
            try WrappedVaultKey.unwrap(withSaltChanged, passphrase: self.passphrase)
        }

        // Still inside the accepted range, so this reaches the tag rather than the clamp.
        var withIterationsChanged = try wrapped()
        withIterationsChanged[36] = 0x00
        withIterationsChanged[37] = 0x03
        withIterationsChanged[38] = 0x0D
        withIterationsChanged[39] = 0x40
        #expect(throws: WrappedVaultKey.WrapError.wrongPassphrase) {
            try WrappedVaultKey.unwrap(withIterationsChanged, passphrase: self.passphrase)
        }
    }

    @Test("An iteration count outside the frozen range is refused before any derivation")
    func iterationsAreClamped() throws {
        var record = try wrapped()

        for bad in [UInt32(1), UInt32(99_999), UInt32(10_000_001), UInt32.max] {
            let bytes = withUnsafeBytes(of: bad.bigEndian, Array.init)
            record.replaceSubrange(36..<40, with: bytes)
            #expect(throws: WrappedVaultKey.WrapError.iterationsOutOfRange(Int(bad))) {
                try WrappedVaultKey.unwrap(record, passphrase: self.passphrase)
            }
        }
    }

    @Test("A writer cannot ask for a count outside the range either")
    func writerRefusesBadIterations() {
        #expect(throws: WrappedVaultKey.WrapError.iterationsOutOfRange(50)) {
            try WrappedVaultKey.wrap(
                vaultKey: self.vaultKey, passphrase: self.passphrase, iterations: 50)
        }
    }

    @Test("Any single altered byte of the sealed key is detected")
    func alterationsAreDetected() throws {
        let record = try wrapped()

        for index in 52..<record.count {
            var altered = record
            altered[index] ^= 0x01
            #expect(throws: WrappedVaultKey.WrapError.wrongPassphrase) {
                try WrappedVaultKey.unwrap(altered, passphrase: self.passphrase)
            }
        }
    }
}
