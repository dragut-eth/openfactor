import Foundation
import Testing

@testable import OpenFactorCore

/// One row of the vector table in
/// [RFC 6238, Appendix B](https://datatracker.ietf.org/doc/html/rfc6238#appendix-B).
struct TOTPVector: Sendable {
    let time: TimeInterval
    let counter: UInt64
    let algorithm: OTPAlgorithm
    let code: String

    var date: Date { Date(timeIntervalSince1970: time) }
}

/// The published table, all three algorithms, 8 digits, 30 second period.
///
/// Note that the three algorithms use **different secrets**. Appendix B says the seed is
/// repeated to the length of the hash function's block, which is 20, 32, and 64 bytes.
/// Running every row against the 20 byte seed is the classic way to get this table wrong,
/// and it fails loudly rather than quietly, which is the only mercy in it.
let rfc6238Vectors: [TOTPVector] = [
    TOTPVector(time: 59, counter: 0x0000_0000_0000_0001, algorithm: .sha1, code: "94287082"),
    TOTPVector(time: 59, counter: 0x0000_0000_0000_0001, algorithm: .sha256, code: "46119246"),
    TOTPVector(time: 59, counter: 0x0000_0000_0000_0001, algorithm: .sha512, code: "90693936"),

    TOTPVector(time: 1_111_111_109, counter: 0x0000_0000_023523EC, algorithm: .sha1, code: "07081804"),
    TOTPVector(time: 1_111_111_109, counter: 0x0000_0000_023523EC, algorithm: .sha256, code: "68084774"),
    TOTPVector(time: 1_111_111_109, counter: 0x0000_0000_023523EC, algorithm: .sha512, code: "25091201"),

    TOTPVector(time: 1_111_111_111, counter: 0x0000_0000_023523ED, algorithm: .sha1, code: "14050471"),
    TOTPVector(time: 1_111_111_111, counter: 0x0000_0000_023523ED, algorithm: .sha256, code: "67062674"),
    TOTPVector(time: 1_111_111_111, counter: 0x0000_0000_023523ED, algorithm: .sha512, code: "99943326"),

    TOTPVector(time: 1_234_567_890, counter: 0x0000_0000_0273EF07, algorithm: .sha1, code: "89005924"),
    TOTPVector(time: 1_234_567_890, counter: 0x0000_0000_0273EF07, algorithm: .sha256, code: "91819424"),
    TOTPVector(time: 1_234_567_890, counter: 0x0000_0000_0273EF07, algorithm: .sha512, code: "93441116"),

    TOTPVector(time: 2_000_000_000, counter: 0x0000_0000_03F940AA, algorithm: .sha1, code: "69279037"),
    TOTPVector(time: 2_000_000_000, counter: 0x0000_0000_03F940AA, algorithm: .sha256, code: "90698825"),
    TOTPVector(time: 2_000_000_000, counter: 0x0000_0000_03F940AA, algorithm: .sha512, code: "38618901"),

    TOTPVector(time: 20_000_000_000, counter: 0x0000_0000_27BC86AA, algorithm: .sha1, code: "65353130"),
    TOTPVector(time: 20_000_000_000, counter: 0x0000_0000_27BC86AA, algorithm: .sha256, code: "77737706"),
    TOTPVector(time: 20_000_000_000, counter: 0x0000_0000_27BC86AA, algorithm: .sha512, code: "47863826"),
]

/// The Appendix B seed for each algorithm, which is the ASCII digits repeated to the
/// length the hash function needs.
func rfc6238Secret(for algorithm: OTPAlgorithm) -> Data {
    let length =
        switch algorithm {
        case .sha1: 20
        case .sha256: 32
        case .sha512: 64
        }

    let digits = "1234567890"
    let repeated = String(repeating: digits, count: length / digits.count + 1)
    return Data(repeated.prefix(length).utf8)
}

@Suite("TOTP")
struct TOTPTests {

    // MARK: - RFC 6238 Appendix B

    @Test("RFC 6238 Appendix B vectors", arguments: rfc6238Vectors)
    func matchesAppendixB(vector: TOTPVector) throws {
        let configuration = try TOTPConfiguration(
            algorithm: vector.algorithm,
            digits: .eight,
            period: 30
        )

        let code = TOTP.code(
            secret: rfc6238Secret(for: vector.algorithm),
            at: vector.date,
            configuration: configuration
        )

        #expect(code == vector.code)
    }

    @Test("RFC 6238 Appendix B counters", arguments: rfc6238Vectors)
    func matchesAppendixBCounters(vector: TOTPVector) {
        #expect(TOTP.counter(at: vector.date, period: 30) == vector.counter)
    }

    /// The Appendix B secrets differ per algorithm. If they were ever collapsed into one,
    /// this is the test that would notice.
    @Test("The Appendix B seeds are the documented lengths", arguments: OTPAlgorithm.allCases)
    func seedsHaveDocumentedLengths(algorithm: OTPAlgorithm) {
        let expected =
            switch algorithm {
            case .sha1: 20
            case .sha256: 32
            case .sha512: 64
            }
        #expect(rfc6238Secret(for: algorithm).count == expected)
        #expect(rfc6238Secret(for: .sha1) == rfcSecret)
    }

    // MARK: - Counter arithmetic

    @Test(
        "The counter advances once per period",
        arguments: [
            (time: 0.0, period: 30, counter: UInt64(0)),
            (time: 29.999, period: 30, counter: UInt64(0)),
            (time: 30.0, period: 30, counter: UInt64(1)),
            (time: 59.0, period: 30, counter: UInt64(1)),
            (time: 60.0, period: 30, counter: UInt64(2)),
            (time: 59.0, period: 60, counter: UInt64(0)),
            (time: 60.0, period: 60, counter: UInt64(1)),
            (time: 100.0, period: 1, counter: UInt64(100)),
        ]
    )
    func advancesOncePerPeriod(time: Double, period: Int, counter: UInt64) {
        #expect(TOTP.counter(at: Date(timeIntervalSince1970: time), period: period) == counter)
    }

    /// A device clock set before 1970 produces codes that work nowhere. The point here is
    /// only that it stays defined instead of trapping on the conversion.
    @Test("A clock set before the epoch does not trap")
    func handlesPreEpochClock() {
        let date = Date(timeIntervalSince1970: -1_000_000)
        #expect(TOTP.counter(at: date, period: 30) == 0)
        #expect(TOTP.timeRemaining(at: date, period: 30) == 30)
    }

    /// The same promise at the other end of the range. Before gate A1 this trapped, since
    /// UInt64(_: Double) crashes on a value past UInt64.max rather than saturating.
    @Test("A clock set absurdly far in the future does not trap")
    func handlesFarFutureClock() {
        for interval in [1e19, 1e20, 1e30, .greatestFiniteMagnitude, Date.distantFuture.timeIntervalSince1970] {
            let date = Date(timeIntervalSince1970: interval)
            _ = TOTP.counter(at: date, period: 30)
            _ = TOTP.timeRemaining(at: date, period: 30)
        }

        #expect(TOTP.counter(at: Date(timeIntervalSince1970: 1e20), period: 30) == UInt64.max / 30)
    }

    // MARK: - Countdown

    @Test(
        "Time remaining counts down through the period",
        arguments: [
            (time: 0.0, remaining: 30.0),
            (time: 1.0, remaining: 29.0),
            (time: 15.0, remaining: 15.0),
            (time: 29.5, remaining: 0.5),
            (time: 30.0, remaining: 30.0),
        ]
    )
    func countsDown(time: Double, remaining: Double) {
        let actual = TOTP.timeRemaining(at: Date(timeIntervalSince1970: time), period: 30)
        #expect(abs(actual - remaining) < 0.000_1)
    }

    /// A fresh code has the whole period ahead of it, so the value is never zero. If it
    /// were, a countdown ring would flash empty for one frame at every change.
    @Test("Time remaining is always positive and never exceeds the period")
    func countdownStaysInRange() {
        for tenth in 0..<1200 {
            let date = Date(timeIntervalSince1970: Double(tenth) / 10)
            let remaining = TOTP.timeRemaining(at: date, period: 30)
            #expect(remaining > 0)
            #expect(remaining <= 30)
        }
    }

    @Test("The code changes exactly when the countdown reaches zero")
    func expiryMatchesTheNextCode() {
        let date = Date(timeIntervalSince1970: 1_234_567_890)
        let expiry = TOTP.expiry(at: date, period: 30)

        #expect(TOTP.counter(at: date, period: 30) + 1 == TOTP.counter(at: expiry, period: 30))
        #expect(
            TOTP.code(secret: rfcSecret, at: date)
                != TOTP.code(secret: rfcSecret, at: expiry)
        )
    }

    /// Every moment inside one period must give the same code, or a user copying a code
    /// near a boundary would get one that is already stale.
    @Test("The code is stable for the whole period")
    func codeIsStableWithinAPeriod() {
        let start = Date(timeIntervalSince1970: 1_234_567_890)
        let expected = TOTP.code(secret: rfcSecret, at: start)

        for second in stride(from: 0.0, to: 30.0, by: 0.5) {
            let code = TOTP.code(secret: rfcSecret, at: start.addingTimeInterval(second))
            #expect(code == expected)
        }
    }
}

@Suite("TOTPConfiguration")
struct TOTPConfigurationTests {

    @Test("The standard configuration is what a bare otpauth URI means")
    func standardMatchesTheDefaults() {
        #expect(TOTPConfiguration.standard.algorithm == .sha1)
        #expect(TOTPConfiguration.standard.digits == .six)
        #expect(TOTPConfiguration.standard.period == 30)
    }

    @Test("An unusable period is refused", arguments: [0, -1, -30, 3601, 86_400])
    func refusesUnusablePeriods(period: Int) {
        #expect(throws: TOTPConfigurationError.invalidPeriod(period)) {
            try TOTPConfiguration(period: period)
        }
    }

    @Test("Periods services actually use are accepted", arguments: [1, 15, 30, 60, 90, 3600])
    func acceptsRealPeriods(period: Int) throws {
        #expect(try TOTPConfiguration(period: period).period == period)
    }
}
