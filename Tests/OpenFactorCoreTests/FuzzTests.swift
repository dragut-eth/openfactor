import Foundation
import Testing

@testable import OpenFactorCore

/// A deterministic pseudo random generator, so a fuzz failure reproduces exactly.
///
/// SplitMix64. Chosen for being a dozen lines with well understood output, not for any
/// cryptographic property, which fuzzing does not need.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The parser and the decoder are the two places arbitrary input enters this code, so
/// they are the two places that get fuzzed. Added at gate A1.
///
/// The contract under test is deliberately weak: every input returns or throws. No
/// crash, no hang, and anything that parses is complete. Correctness on valid input is
/// the other suites' job.
@Suite("Fuzzing")
struct FuzzTests {

    // MARK: - Base32

    @Test("Random strings cannot crash the Base32 decoder")
    func base32SurvivesRandomStrings() {
        var random = SplitMix64(seed: 0xB32)

        // Characters weighted toward the interesting ones: the alphabet, padding,
        // separators, digits the alphabet excludes, and some unicode.
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567abcdefgh=- 018!%:/€🔐\u{0}")

        for _ in 0..<5_000 {
            let length = Int(random.next() % 40)
            let text = String((0..<length).map { _ in characters.randomElement(using: &random)! })

            _ = try? Base32.decode(text)
        }
    }

    @Test("Random bytes always round trip through Base32")
    func base32RoundTripsRandomBytes() throws {
        var random = SplitMix64(seed: 0x0B32)

        for _ in 0..<2_000 {
            let length = Int(random.next() % 128)
            let bytes = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: random.next()) })

            #expect(try Base32.decode(Base32.encode(bytes)) == bytes)
            #expect(try Base32.decode(Base32.encode(bytes, padded: false)) == bytes)
        }
    }

    // MARK: - The URI parser

    /// Valid URIs with random single character edits, which is the mutation most likely
    /// to land in the gap between two validation rules.
    @Test("Mutated URIs cannot crash the parser or half parse")
    func parserSurvivesMutations() {
        var random = SplitMix64(seed: 0xF0221)

        let seeds = [
            "otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example",
            "otpauth://totp/A?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60",
            "otpauth://hotp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&counter=42",
            "otpauth://totp/Amazon%20Web%20Services:user?secret=JBSWY3DPEHPK3PXP",
        ]
        let noise = Array("otpauth:/?&=%:🔐 \u{0}ABCdef123")

        for _ in 0..<5_000 {
            var characters = Array(seeds.randomElement(using: &random)!)

            for _ in 0...Int(random.next() % 4) {
                switch random.next() % 3 {
                case 0 where !characters.isEmpty:
                    characters.remove(at: Int(random.next() % UInt64(characters.count)))
                case 1 where !characters.isEmpty:
                    characters[Int(random.next() % UInt64(characters.count))] = noise.randomElement(using: &random)!
                default:
                    characters.insert(
                        noise.randomElement(using: &random)!,
                        at: Int(random.next() % UInt64(characters.count + 1))
                    )
                }
            }

            if let account = try? OTPAuthURI.account(from: String(characters)) {
                // Whatever survives mutation must be a complete account, never a partial
                // one. The secret is the field a half parse would leave empty.
                #expect(!account.secret.isEmpty)
            }
        }
    }

    @Test("Random garbage cannot crash the parser")
    func parserSurvivesGarbage() {
        var random = SplitMix64(seed: 0x6A21BA6E)

        for _ in 0..<5_000 {
            let length = Int(random.next() % 200)
            let bytes = Data((0..<length).map { _ in UInt8(truncatingIfNeeded: random.next()) })
            let text = String(decoding: bytes, as: UTF8.self)

            _ = try? OTPAuthURI.account(from: "otpauth://" + text)
            _ = try? OTPAuthURI.account(from: text)
        }
    }

    /// Serialization then parsing, over randomly built valid accounts. The writer and the
    /// parser were reviewed together at gate A1, and this is the executable form of the
    /// claim that they agree.
    @Test("Randomly built accounts always round trip")
    func randomAccountsRoundTrip() throws {
        var random = SplitMix64(seed: 0xACC0)
        let alphabet = Array("abcdefghijklmnop qrstuvwxyz:@/%&=?#éü🔐")

        func randomText(upTo limit: Int) -> String {
            String((0..<Int(random.next() % UInt64(limit))).map { _ in alphabet.randomElement(using: &random)! })
        }

        for _ in 0..<1_000 {
            let secret = Data((0..<(1 + Int(random.next() % 64))).map { _ in UInt8(truncatingIfNeeded: random.next()) })

            let generator: OTPGenerator =
                if random.next() % 4 == 0 {
                    .hotp(
                        counter: random.next(),
                        digits: OTPDigits.allCases.randomElement(using: &random)!,
                        algorithm: OTPAlgorithm.allCases.randomElement(using: &random)!
                    )
                } else {
                    .totp(
                        try TOTPConfiguration(
                            algorithm: OTPAlgorithm.allCases.randomElement(using: &random)!,
                            digits: OTPDigits.allCases.randomElement(using: &random)!,
                            period: 1 + Int(random.next() % 3600)
                        )
                    )
                }

            let original = OTPAccount(
                issuer: random.next() % 3 == 0 ? nil : randomText(upTo: 30),
                name: randomText(upTo: 30),
                secret: secret,
                generator: generator
            )

            let parsed = try OTPAuthURI.account(from: OTPAuthURI.uri(for: original))

            // Whitespace at the edges of a name or issuer is trimmed on the way back in,
            // which is the parser being deliberately tolerant, so the comparison trims
            // too. Everything else must survive exactly.
            #expect(parsed.secret == original.secret)
            #expect(parsed.generator == original.generator)
            #expect(parsed.name == original.name.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(
                parsed.issuer
                    == original.issuer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }
    }
}
