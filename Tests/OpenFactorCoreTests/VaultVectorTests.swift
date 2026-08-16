import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The published vault vectors, run against this implementation.
///
/// `docs/VAULT.md` carries these bytes and is normative. They exist for the reason the archive's
/// do: **the format has to survive a rewrite.** Round trip tests prove an implementation agrees
/// with itself, which is exactly what a format break also does. These prove it agrees with the
/// bytes on the page, so a change that alters the layout fails here rather than in somebody's
/// vault a year from now.
///
/// Nonces and salts are fixed so the output is reproducible. **A real record generates both from
/// the system CSPRNG and never reuses either**, which is asserted separately.
@Suite("Vault test vectors")
struct VaultVectorTests {

    private func bytes(_ hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - The account record

    private let recordKey = SymmetricKey(data: Data((0..<32).map(UInt8.init)))
    private let recordID = UUID(uuidString: "6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F")!
    private let recordMetadata = Data(#"{"color":"blue","issuer":"GitHub","name":"octocat"}"#.utf8)
    private let recordSecret = Data("12345678901234567890".utf8)

    private let accountVector = """
        4f465631a0a1a2a3a4a5a6a7a8a9aaab00000090e6187c1e3ee961d00e0af5f13d58a2b205c97b3cb0de\
        311fe96b54a445893268a63e329d8d0e71533ef161ea3358ec9a3374252916f2677e415e0b5ea47085b0\
        b4bc856f30a5e4e0f4e2ff188fceccbacd0baba4c5c1997aee753e9ab19a4d948f842bab03ae8f9b9edb\
        06508588ed28245061aede359b3c2fcfdea4b455f24d3a0515a871126b350b9da248b8860917b0b1b2b3\
        b4b5b6b7b8b9babb0000009099555abfddff886b72cea09af46db9f0b7087ce42216b6055ece82f15c82\
        f216054b233a63dea6b8a55ba04a3cb982b52d6d17c71b3b42f04d8a6c30049b20ffb2e83eb40abc66da\
        19dca25e9e06e2314690c9b2a87875ddf5fb78902b590fbf63a07e5bced736165e4e1adc92dac0800db6\
        b79773f3cd3a7807f7d91e0e2f2289b1b05aab1d368d0fb8593b65c346fb
        """

    @Test("Sealing the vector inputs reproduces the published account record")
    func accountRecordReproduces() throws {
        let record = try VaultRecord.seal(
            metadata: recordMetadata, secret: recordSecret, id: recordID, key: recordKey,
            metadataNonce: try AES.GCM.Nonce(data: Data((0xA0...0xAB).map(UInt8.init))),
            secretNonce: try AES.GCM.Nonce(data: Data((0xB0...0xBB).map(UInt8.init))))

        #expect(hex(record) == accountVector)
        #expect(record.count == 324)
    }

    @Test("The published account record opens to the published inputs")
    func accountRecordOpens() throws {
        let record = bytes(accountVector)

        #expect(try VaultRecord.openMetadata(record, id: recordID, key: recordKey) == recordMetadata)
        #expect(try VaultRecord.openSecret(record, id: recordID, key: recordKey) == recordSecret)
    }

    // MARK: - The wrapped key

    private let wrappedVaultKey = SymmetricKey(data: Data(repeating: 0x2A, count: 32))
    private let wrappedPassphrase = "YZTR-THFW-WT6E-OXIV-73XD-QCDM"

    private let wrappedVector = """
        4f464b31c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf000927c0d0d1\
        d2d3d4d5d6d7d8d9dadb01a685bb1548f10f769b3bc1a1b7fe0a47ca50d52f06e4fd25a85b77ea3b299d\
        dfa536edb22eb16fea7eb8d4c7eea3bf
        """

    @Test("Wrapping the vector inputs reproduces the published record")
    func wrappedKeyReproduces() throws {
        let record = try WrappedVaultKey.wrap(
            vaultKey: wrappedVaultKey, passphrase: wrappedPassphrase, iterations: 600_000,
            salt: Data((0..<32).map { UInt8(0xC0 &+ $0) }),
            nonce: try AES.GCM.Nonce(data: Data((0xD0...0xDB).map(UInt8.init))))

        #expect(hex(record) == wrappedVector)
        #expect(record.count == 100)
    }

    @Test("The published wrapped key unwraps to the published vault key")
    func wrappedKeyUnwraps() throws {
        let recovered = try WrappedVaultKey.unwrap(
            bytes(wrappedVector), passphrase: wrappedPassphrase)

        #expect(
            recovered.withUnsafeBytes { Data($0) }
                == wrappedVaultKey.withUnsafeBytes { Data($0) })
    }

    /// The count is inside the record and inside its additional data, so the vector also pins
    /// that a reader takes it from the bytes rather than assuming the number it writes with.
    @Test("The vector carries its iteration count where a reader must look")
    func iterationCountIsInTheRecord() {
        let record = bytes(wrappedVector)
        let stored = record[36..<40].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        #expect(stored == 600_000)
    }

    // MARK: - What the vectors do not excuse

    /// The vectors fix the nonces to be reproducible, which is the one way a vector can mislead:
    /// somebody could satisfy every assertion above with a writer that used constants.
    @Test("The real writers never reuse a nonce or a salt")
    func realWritersAreRandom() throws {
        var metadataNonces: Set<Data> = []
        var salts: Set<Data> = []

        for _ in 0..<6 {
            let record = try VaultRecord.seal(
                metadata: recordMetadata, secret: recordSecret, id: recordID, key: recordKey)
            metadataNonces.insert(record[4..<16])

            let wrapped = try WrappedVaultKey.wrap(
                vaultKey: wrappedVaultKey, passphrase: wrappedPassphrase, iterations: 100_000)
            salts.insert(wrapped[4..<36])
        }

        #expect(metadataNonces.count == 6)
        #expect(salts.count == 6)
    }
}
