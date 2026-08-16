import CryptoKit
import Foundation
import Testing

@testable import OpenFactorCore

/// The account record, byte for byte.
///
/// `docs/VAULT.md` pins this layout because an external review pointed out that a page calling
/// itself normative while describing the record conceptually leaves the first implementation to
/// become the specification by accident. So these tests assert the *layout* as well as the
/// round trip: a change that still round trips but moves a field is a format break, and format
/// breaks are what this project cannot fix after people have data.
@Suite("Vault record")
struct VaultRecordTests {

    private let key = SymmetricKey(data: Data(repeating: 0xA5, count: 32))
    private let other = SymmetricKey(data: Data(repeating: 0x5A, count: 32))
    private let id = UUID(uuidString: "6F1B0C0A-6D3A-4A1F-9A2E-2A3B4C5D6E7F")!
    private let metadata = Data(#"{"issuer":"GitHub","name":"octocat"}"#.utf8)
    private let secret = Data("12345678901234567890".utf8)

    private func sealed() throws -> Data {
        try VaultRecord.seal(metadata: metadata, secret: secret, id: id, key: key)
    }

    // MARK: - The layout

    @Test("The record begins with its magic and its halves are where the page says")
    func layoutIsExact() throws {
        let record = try sealed()

        #expect(record.prefix(4) == Data("OFV1".utf8))

        // Both payloads pad to a whole bucket, then gain a 16 byte tag.
        let metadataLength = record[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(metadataLength == UInt32(VaultPadding.bucket + VaultRecord.tagSize))

        let secretStart = 20 + Int(metadataLength)
        let secretLength = record[(secretStart + 12)..<(secretStart + 16)]
            .reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(secretLength == UInt32(VaultPadding.bucket + VaultRecord.tagSize))

        #expect(record.count == 20 + Int(metadataLength) + 16 + Int(secretLength))
    }

    /// The property the two halves exist for. A list must cost metadata and nothing else, and
    /// the only way to assert that from outside is that the halves are independently sealed.
    @Test("Opening the metadata never touches the secret half")
    func metadataOpensAlone() throws {
        var record = try sealed()

        // Destroy the secret half entirely. Metadata must still open.
        record[record.count - 1] ^= 0xFF

        #expect(try VaultRecord.openMetadata(record, id: id, key: key) == metadata)
        #expect(throws: VaultRecord.RecordError.wrongKeyOrTampered) {
            try VaultRecord.openSecret(record, id: self.id, key: self.key)
        }
    }

    @Test("A sealed account round trips")
    func roundTrips() throws {
        let record = try sealed()

        #expect(try VaultRecord.openMetadata(record, id: id, key: key) == metadata)
        #expect(try VaultRecord.openSecret(record, id: id, key: key) == secret)
    }

    @Test("Empty and large payloads round trip", arguments: [0, 1, 127, 128, 129, 5000])
    func handlesEveryLength(count: Int) throws {
        let payload = Data(repeating: 0x7E, count: count)
        let record = try VaultRecord.seal(metadata: payload, secret: payload, id: id, key: key)

        #expect(try VaultRecord.openMetadata(record, id: id, key: key) == payload)
        #expect(try VaultRecord.openSecret(record, id: id, key: key) == payload)
    }

    // MARK: - What must fail

    @Test("The wrong key opens nothing")
    func wrongKeyFails() throws {
        let record = try sealed()

        #expect(throws: VaultRecord.RecordError.wrongKeyOrTampered) {
            try VaultRecord.openMetadata(record, id: self.id, key: self.other)
        }
        #expect(throws: VaultRecord.RecordError.wrongKeyOrTampered) {
            try VaultRecord.openSecret(record, id: self.id, key: self.other)
        }
    }

    /// The UUID is bound as additional data so a writer cannot move one account's ciphertext
    /// onto another account, which would otherwise decrypt cleanly under the wrong name.
    @Test("A record cannot be moved to another account")
    func recordIsBoundToItsAccount() throws {
        let record = try sealed()
        let elsewhere = UUID()

        #expect(throws: VaultRecord.RecordError.wrongKeyOrTampered) {
            try VaultRecord.openMetadata(record, id: elsewhere, key: self.key)
        }
    }

    /// Domain separation. Both halves are sealed under one key, so without distinct additional
    /// data a metadata half and a secret half would be interchangeable.
    @Test("The two halves cannot be substituted for one another")
    func halvesAreDomainSeparated() throws {
        // Seal a record whose halves are byte identical, so only the AAD distinguishes them.
        let same = Data("identical".utf8)
        let record = try VaultRecord.seal(metadata: same, secret: same, id: id, key: key)

        let split = record.count / 2
        #expect(
            record.prefix(split) != record.suffix(from: split),
            "identical plaintexts must not produce identical halves")
    }

    @Test("Anything that is not a record is refused as one")
    func rejectsNonRecords() {
        for bytes in [Data(), Data("OFV".utf8), Data("XXXX".utf8), Data(repeating: 0, count: 40)] {
            #expect(throws: (any Error).self) {
                try VaultRecord.openMetadata(bytes, id: self.id, key: self.key)
            }
        }
    }

    /// An item is attacker writable, so a length claiming more than exists is ordinary input.
    @Test("A truncated record is refused rather than half read")
    func refusesTruncation() throws {
        let record = try sealed()

        for length in 1..<record.count {
            #expect(throws: (any Error).self) {
                try VaultRecord.openMetadata(record.prefix(length), id: self.id, key: self.key)
            }
        }
    }

    @Test("A length that lies is refused, not allocated")
    func refusesLyingLengths() throws {
        var record = try sealed()
        // Claim four gigabytes of metadata.
        record[16] = 0xFF; record[17] = 0xFF; record[18] = 0xFF; record[19] = 0xFF

        #expect(throws: VaultRecord.RecordError.truncated) {
            try VaultRecord.openMetadata(record, id: self.id, key: self.key)
        }
    }

    // MARK: - Replacing metadata

    /// The method a rename, a reorder and an HOTP counter go through, and the reason none of
    /// them decrypts a secret.
    @Test("Replacing metadata leaves the secret half byte for byte identical")
    func replacementCopiesTheSecretVerbatim() throws {
        let record = try sealed()
        let renamed = Data(#"{"issuer":"Fastmail","name":"someone"}"#.utf8)

        let updated = try VaultRecord.replacingMetadata(
            in: record, with: renamed, id: id, key: key)

        #expect(try VaultRecord.openMetadata(updated, id: id, key: key) == renamed)
        #expect(try VaultRecord.openSecret(updated, id: id, key: key) == secret)

        // The bytes, not merely the plaintext: the secret half was moved unexamined.
        let originalSecretHalf = record.suffix(VaultPadding.bucket + VaultRecord.tagSize + 16)
        let updatedSecretHalf = updated.suffix(VaultPadding.bucket + VaultRecord.tagSize + 16)
        #expect(originalSecretHalf == updatedSecretHalf)
    }

    @Test("Replacing metadata uses a fresh nonce every time")
    func replacementRefreshesTheMetadataNonce() throws {
        var record = try sealed()
        var nonces: Set<Data> = [record[4..<16]]

        for index in 0..<8 {
            record = try VaultRecord.replacingMetadata(
                in: record, with: Data("round \(index)".utf8), id: id, key: key)
            nonces.insert(record[4..<16])
        }

        #expect(nonces.count == 9, "a repeated nonce under one key is the catastrophic mistake")
    }

    @Test("Replacing metadata on something that is not a record fails")
    func replacementRefusesNonRecords() {
        #expect(throws: (any Error).self) {
            try VaultRecord.replacingMetadata(
                in: Data("nope".utf8), with: Data(), id: self.id, key: self.key)
        }
    }
}
