import Foundation
import Testing

@testable import OpenFactorCore

/// The shared secret used throughout RFC 4226 and RFC 6238, as ASCII.
let rfcSecret = Data("12345678901234567890".utf8)

@Suite("HOTP")
struct HOTPTests {

    // MARK: - RFC 4226 Appendix D

    /// The published vector table. Counter 0 through 9 against the standard secret,
    /// 6 digits, SHA1. If a change breaks one of these, the change is wrong.
    static let appendixD = [
        "755224", "287082", "359152", "969429", "338314",
        "254676", "287922", "162583", "399871", "520489",
    ]

    @Test("RFC 4226 Appendix D vectors", arguments: Array(appendixD.enumerated()))
    func matchesAppendixD(vector: (offset: Int, element: String)) {
        let code = HOTP.code(secret: rfcSecret, counter: UInt64(vector.offset))
        #expect(code == vector.element)
    }

    // MARK: - Truncation

    /// The worked example in RFC 4226 section 5.4, which starts from a fixed HMAC value
    /// rather than computing one. It pins the truncation step on its own, so a failure
    /// points at the arithmetic rather than at the HMAC.
    @Test("The RFC 4226 section 5.4 truncation example")
    func matchesTruncationExample() throws {
        let hmac = try #require(Data(hexadecimal: "1f8698690e02ca16618550ef7f19da8e945b555a"))

        // The low 4 bits of the last byte, 0x5a, give offset 10. The four bytes there are
        // 50 ef 7f 19, and the top bit is masked off.
        #expect(HOTP.truncate(hmac) == 0x50EF_7F19)
        #expect(HOTP.truncate(hmac) == 1_357_872_921)
    }

    /// The offset comes from 4 bits, so it is at most 15, and the read is 4 bytes wide.
    /// A 20 byte SHA1 digest is the shortest hash in use and is therefore the tight case.
    @Test("Truncation stays in bounds for every possible offset")
    func truncationStaysInBounds() {
        for offset in 0...15 {
            var bytes = [UInt8](repeating: 0xFF, count: 20)
            bytes[19] = UInt8(0xF0 | offset)
            #expect(HOTP.truncate(Data(bytes)) > 0)
        }
    }

    // MARK: - Digits

    @Test("Codes are padded to the requested length", arguments: OTPDigits.allCases)
    func padsToRequestedLength(digits: OTPDigits) {
        for counter in UInt64(0)..<200 {
            let code = HOTP.code(secret: rfcSecret, counter: counter, digits: digits)
            #expect(code.count == digits.rawValue)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }

    /// A code is text, not a number. Dropping a leading zero would produce a five
    /// character code that the service rejects, and it is the kind of bug that only
    /// shows up for one user in ten.
    @Test("Leading zeros are kept")
    func keepsLeadingZeros() {
        // Counter 8_899 happens to truncate to a value below 100_000 with this secret.
        let codes = (UInt64(0)..<20_000).map { HOTP.code(secret: rfcSecret, counter: $0) }
        let padded = codes.filter { $0.hasPrefix("0") }

        #expect(!padded.isEmpty, "Expected at least one code needing a leading zero")
        #expect(padded.allSatisfy { $0.count == 6 })
    }

    // MARK: - Algorithms

    @Test("Each algorithm produces a different code", arguments: OTPAlgorithm.allCases)
    func generatesForEveryAlgorithm(algorithm: OTPAlgorithm) {
        let code = HOTP.code(secret: rfcSecret, counter: 1, algorithm: algorithm)
        #expect(code.count == 6)
    }

    @Test("Changing the algorithm changes the code")
    func algorithmChangesTheCode() {
        let codes = Set(OTPAlgorithm.allCases.map {
            HOTP.code(secret: rfcSecret, counter: 1, algorithm: $0)
        })
        #expect(codes.count == OTPAlgorithm.allCases.count)
    }
}

// MARK: - Helpers

extension Data {
    /// Parses a hexadecimal string, for test vectors that are published as hex.
    init?(hexadecimal string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        self.init(bytes)
    }
}
