import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

/// The order and the grouping the watch list is built on.
///
/// Worth asserting rather than eyeballing, because the wrong answer here is invisible on the
/// device: a wearer sees a list, not a list in a particular order, and a counter based
/// account that quietly failed to sink to the bottom looks exactly like one that did.
///
/// The stability half matters more than it looks. Sorting on a boolean is only stable if the
/// sort is, and the thing being preserved is the wearer's own ordering inside each group. A
/// comparator that shuffled the time based accounts among themselves would still put every
/// counter based one last, and pass any test that only checked the grouping.
@Suite("Watch list ordering")
struct WatchListTests {

    private func record(
        _ issuer: String,
        timeBased: Bool,
        sortIndex: Int = 0
    ) throws -> AccountRecord {
        let generator: OTPGenerator =
            timeBased
            ? .totp(try TOTPConfiguration(algorithm: .sha1, digits: .six, period: 30))
            : .hotp(counter: 0, digits: .six, algorithm: .sha1)

        return AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: issuer,
                name: "octocat",
                generator: generator,
                color: .blue,
                sortIndex: sortIndex
            )
        )
    }

    @Test("A counter based account is the one the watch cannot finish")
    func namesTheOnesThatNeedThePhone() throws {
        #expect(WatchList.needsPhone(try record("HOTP", timeBased: false)))
        #expect(!WatchList.needsPhone(try record("TOTP", timeBased: true)))
    }

    @Test("Counter based accounts sink below the ones that work here")
    func sinksCounterBasedAccounts() throws {
        let records = [
            try record("Counter one", timeBased: false, sortIndex: 0),
            try record("Time one", timeBased: true, sortIndex: 1),
            try record("Counter two", timeBased: false, sortIndex: 2),
            try record("Time two", timeBased: true, sortIndex: 3),
        ]

        let issuers = WatchList.ordered(records).map(\.metadata.displayIssuer)

        #expect(issuers == ["Time one", "Time two", "Counter one", "Counter two"])
    }

    @Test("The wearer's own order survives inside each group")
    func preservesOrderWithinEachGroup() throws {
        let records = try (1...6).map {
            try record("Account \($0)", timeBased: $0.isMultiple(of: 2), sortIndex: $0)
        }

        let ordered = WatchList.ordered(records).map(\.metadata.displayIssuer)

        #expect(ordered == ["Account 2", "Account 4", "Account 6",
                            "Account 1", "Account 3", "Account 5"])
    }

    @Test("A list of one kind is returned unchanged")
    func leavesUniformListsAlone() throws {
        let timeBased = try (1...3).map {
            try record("Time \($0)", timeBased: true, sortIndex: $0)
        }
        let counterBased = try (1...3).map {
            try record("Counter \($0)", timeBased: false, sortIndex: $0)
        }

        #expect(WatchList.ordered(timeBased).map(\.id) == timeBased.map(\.id))
        #expect(WatchList.ordered(counterBased).map(\.id) == counterBased.map(\.id))
        #expect(WatchList.ordered([]).isEmpty)
    }
}
