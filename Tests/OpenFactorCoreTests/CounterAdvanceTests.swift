import Foundation
import Testing

@testable import OpenFactorCore

/// Advancing a counter based account, written to the rules recorded as finding F4 at gate
/// A1: checked arithmetic, the counter persisted before the code is handed back, and one
/// store call rather than a metadata update that a caller could get wrong.
@Suite("Counter advancement")
struct CounterAdvanceTests {

    private func store(startingAt counter: UInt64 = 0) throws -> (InMemorySecretStore, AccountRecord) {
        let store = InMemorySecretStore()
        let record = try store.add(
            OTPAccount(
                issuer: "Example",
                name: "counter",
                secret: rfcSecret,
                generator: .hotp(counter: counter, digits: .six, algorithm: .sha1)
            ),
            color: .blue
        )
        return (store, record)
    }

    /// Walking the RFC 4226 Appendix D table one advance at a time, which checks the
    /// counter arithmetic and the generation together rather than either alone.
    @Test("Advancing walks the published vector table")
    func advancingWalksAppendixD() throws {
        let (store, first) = try store()
        var record = first

        // The account starts at counter 0, so the first advance produces counter 1.
        let expected = ["287082", "359152", "969429", "338314", "254676"]

        for code in expected {
            let result = try store.advancingCounter(for: record)
            record = result.record
            #expect(result.code == code)
        }
    }

    /// The rule from F4. If the counter were stored after the code were shown, a crash in
    /// between would repeat a code the service has already consumed, and a replayed
    /// counter is refused with no explanation the user can act on.
    @Test("The new counter is persisted, not just returned")
    func persistsTheNewCounter() throws {
        let (store, record) = try store()

        _ = try store.advancingCounter(for: record)

        let stored = try #require(try store.records().readable.first)
        #expect(stored.metadata.generator == .hotp(counter: 1, digits: .six, algorithm: .sha1))
    }

    @Test("The returned record carries the new counter too")
    func returnsTheUpdatedRecord() throws {
        let (store, record) = try store(startingAt: 41)

        let result = try store.advancingCounter(for: record)

        #expect(result.record.metadata.generator == .hotp(counter: 42, digits: .six, algorithm: .sha1))
        #expect(result.record.id == record.id)
    }

    /// **Enrolment's ceiling and advancing's ceiling were two different numbers**, and nothing
    /// connected them. A counter accepted at `AccountLimits.maximumCounter` advanced to one past
    /// the largest integer the backup format can carry, and the encrypted export then refused the
    /// whole vault. Audit X3, OF-X3-03.
    @Test("A counter at the storage ceiling refuses to advance past it, and changes nothing")
    func refusesToLeaveTheStorableRange() throws {
        let (store, record) = try store(startingAt: AccountLimits.maximumCounter)

        #expect(throws: SecretStoreError.counterExhausted) {
            try store.advancingCounter(for: record)
        }

        let stored = try #require(try store.records().readable.first)
        #expect(
            stored.metadata.generator
                == .hotp(counter: AccountLimits.maximumCounter, digits: .six, algorithm: .sha1))
        #expect(AccountLimits.isStorable(try store.account(for: record.id)), "still exportable")
    }

    /// Wrapping would send the account back to counter zero and replay every code it has
    /// ever produced. Unreachable by a human, and the check costs nothing.
    @Test("A counter at its maximum refuses to wrap")
    func refusesToWrap() throws {
        let (store, record) = try store(startingAt: .max)

        #expect(throws: SecretStoreError.counterExhausted) {
            try store.advancingCounter(for: record)
        }

        let stored = try #require(try store.records().readable.first)
        #expect(
            stored.metadata.generator == .hotp(counter: .max, digits: .six, algorithm: .sha1),
            "A refused advance must not have changed anything"
        )
    }

    @Test("A time based account cannot be advanced")
    func refusesTimeBasedAccounts() throws {
        let store = InMemorySecretStore()
        let record = try store.add(
            OTPAccount(issuer: "Example", name: "timed", secret: rfcSecret, generator: .totp(.standard)),
            color: .blue
        )

        #expect(throws: SecretStoreError.notCounterBased) {
            try store.advancingCounter(for: record)
        }
    }

    @Test("Advancing an account that is gone fails")
    func refusesMissingAccounts() {
        let store = InMemorySecretStore()
        let ghost = AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: nil,
                name: "ghost",
                generator: .hotp(counter: 0, digits: .six, algorithm: .sha1),
                color: .blue,
                sortIndex: 0
            )
        )

        #expect(throws: SecretStoreError.notFound) {
            try store.advancingCounter(for: ghost)
        }
    }

    /// Advancing must not disturb the other settings, or the codes silently stop matching.
    @Test("Advancing preserves the algorithm and digit count")
    func preservesOtherSettings() throws {
        let store = InMemorySecretStore()
        let record = try store.add(
            OTPAccount(
                issuer: "Example",
                name: "counter",
                secret: rfcSecret,
                generator: .hotp(counter: 7, digits: .eight, algorithm: .sha512)
            ),
            color: .blue
        )

        let result = try store.advancingCounter(for: record)

        #expect(result.record.metadata.generator == .hotp(counter: 8, digits: .eight, algorithm: .sha512))
        #expect(result.code.count == 8)
    }

    @Test("Advancing does not touch the secret")
    func preservesTheSecret() throws {
        let (store, record) = try store()

        _ = try store.advancingCounter(for: record)

        #expect(try store.secret(for: record.id) == rfcSecret)
    }
}
