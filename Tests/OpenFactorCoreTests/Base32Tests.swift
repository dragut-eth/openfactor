import Foundation
import Testing

@testable import OpenFactorCore

/// One row of the test vector table in
/// [RFC 4648, section 10](https://datatracker.ietf.org/doc/html/rfc4648#section-10).
struct Base32Vector: Sendable {
    let plain: String
    let encoded: String

    var bytes: Data { Data(plain.utf8) }
}

/// The complete published vector table. These are the authority: if a change breaks one
/// of these, the change is wrong, not the vector.
let rfc4648Vectors: [Base32Vector] = [
    Base32Vector(plain: "", encoded: ""),
    Base32Vector(plain: "f", encoded: "MY======"),
    Base32Vector(plain: "fo", encoded: "MZXQ===="),
    Base32Vector(plain: "foo", encoded: "MZXW6==="),
    Base32Vector(plain: "foob", encoded: "MZXW6YQ="),
    Base32Vector(plain: "fooba", encoded: "MZXW6YTB"),
    Base32Vector(plain: "foobar", encoded: "MZXW6YTBOI======"),
]

@Suite("Base32")
struct Base32Tests {

    // MARK: - The published vectors

    @Test("RFC 4648 vectors decode", arguments: rfc4648Vectors)
    func decodesPublishedVectors(vector: Base32Vector) throws {
        #expect(try Base32.decode(vector.encoded) == vector.bytes)
    }

    @Test("RFC 4648 vectors encode", arguments: rfc4648Vectors)
    func encodesPublishedVectors(vector: Base32Vector) {
        #expect(Base32.encode(vector.bytes) == vector.encoded)
    }

    @Test("RFC 4648 vectors decode without padding", arguments: rfc4648Vectors)
    func decodesPublishedVectorsUnpadded(vector: Base32Vector) throws {
        let unpadded = vector.encoded.replacingOccurrences(of: "=", with: "")
        #expect(try Base32.decode(unpadded) == vector.bytes)
    }

    @Test("Encoding can omit padding", arguments: rfc4648Vectors)
    func encodesWithoutPadding(vector: Base32Vector) {
        let expected = vector.encoded.replacingOccurrences(of: "=", with: "")
        #expect(Base32.encode(vector.bytes, padded: false) == expected)
    }

    /// The seed used throughout RFC 6238, which PR 2 will generate codes from. Decoding
    /// it correctly here is what makes those tests meaningful.
    @Test("The RFC 6238 seed decodes to its ASCII bytes")
    func decodesTOTPSeed() throws {
        let seed = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        #expect(try Base32.decode(seed) == Data("12345678901234567890".utf8))
    }

    // MARK: - How secrets are really presented

    @Test(
        "Secrets are accepted however they are formatted",
        arguments: [
            "mzxw6ytboi",
            "MZXW 6YTB OI",
            "mzxw-6ytb-oi",
            "  MZXW6YTBOI  ",
            "MZXW6YTBOI======",
            "mzxw 6ytb oi======",
        ]
    )
    func acceptsRealWorldFormatting(text: String) throws {
        #expect(try Base32.decode(text) == Data("foobar".utf8))
    }

    @Test("An empty secret decodes to no bytes")
    func decodesEmpty() throws {
        #expect(try Base32.decode("").isEmpty)
    }

    // MARK: - Rejection

    @Test(
        "Characters outside the alphabet are rejected",
        arguments: [
            ("AB0C", Character("0"), 2),
            ("AB1C", Character("1"), 2),
            ("AB8C", Character("8"), 2),
            ("AB9C", Character("9"), 2),
            ("MZXW6YTB!!", Character("!"), 8),
        ]
    )
    func rejectsInvalidCharacters(text: String, character: Character, offset: Int) {
        #expect(throws: Base32Error.invalidCharacter(character, offset: offset)) {
            try Base32.decode(text)
        }
    }

    /// A group of 1, 3, or 6 characters cannot come out of any input, so it means
    /// characters were lost between the service and here.
    @Test("Impossible lengths are rejected", arguments: [1, 3, 6, 9, 11, 14])
    func rejectsImpossibleLengths(length: Int) {
        let text = String(repeating: "A", count: length)
        #expect(throws: Base32Error.invalidLength(length)) {
            try Base32.decode(text)
        }
    }

    @Test(
        "Malformed padding is rejected",
        arguments: [
            "=MZXW6YTB",     // padding at the start
            "MZ=XW6YTB",     // padding in the middle
            "MY=",           // padded, but not a whole group
            "MZXW6YTBOI=",   // padded, but not a whole group
        ]
    )
    func rejectsMalformedPadding(text: String) {
        #expect(throws: Base32Error.invalidPadding) {
            try Base32.decode(text)
        }
    }

    // MARK: - Leftover bits

    /// A 26 character secret carries 16 bytes plus 2 bits that belong to no byte. Some
    /// services set those bits, some do not, and the same 16 bytes come out either way.
    /// See the note in ``Base32/decode(_:)``.
    @Test("Leftover bits are discarded rather than rejected")
    func discardsLeftoverBits() throws {
        let zeroLeftoverBits = "MZXW6YTBOIMZXW6YTBOIMZXW6Y"
        let setLeftoverBits = "MZXW6YTBOIMZXW6YTBOIMZXW6Z"

        let first = try Base32.decode(zeroLeftoverBits)
        let second = try Base32.decode(setLeftoverBits)

        #expect(first.count == 16)
        #expect(first == second)
    }

    // MARK: - Round trip

    @Test("Encoding then decoding returns the original bytes", arguments: 0...40)
    func roundTrips(length: Int) throws {
        // A fixed sequence rather than random bytes, so a failure is reproducible.
        let bytes = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })

        #expect(try Base32.decode(Base32.encode(bytes)) == bytes)
        #expect(try Base32.decode(Base32.encode(bytes, padded: false)) == bytes)
    }

    @Test("Padded encoding is always a whole number of groups", arguments: 0...40)
    func padsToWholeGroups(length: Int) {
        let bytes = Data(repeating: 0xAB, count: length)
        #expect(Base32.encode(bytes).count % 8 == 0)
    }
}
