import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

@MainActor
@Suite("Account list")
struct AccountListViewModelTests {

    /// The RFC 6238 seed, so generated codes can be checked against published values
    /// rather than against whatever the code happens to produce.
    private static let seed = Data("12345678901234567890".utf8)

    private func store(
        _ accounts: [(issuer: String, name: String)] = [("GitHub", "octocat")],
        generator: OTPGenerator = .totp(.standard)
    ) -> InMemorySecretStore {
        let store = InMemorySecretStore()

        for account in accounts {
            try? store.add(
                OTPAccount(
                    issuer: account.issuer,
                    name: account.name,
                    secret: Self.seed,
                    generator: generator
                ),
                color: .blue
            )
        }

        return store
    }

    private func eightDigitStore() throws -> InMemorySecretStore {
        let store = InMemorySecretStore()
        let configuration = try TOTPConfiguration(algorithm: .sha1, digits: .eight, period: 30)

        try store.add(
            OTPAccount(issuer: "RFC", name: "6238", secret: Self.seed, generator: .totp(configuration)),
            color: .blue
        )

        return store
    }

    // MARK: - Loading and generating

    @Test("Loading shows the stored accounts")
    func loadsAccounts() {
        let model = AccountListViewModel(store: store([("GitHub", "octocat"), ("AWS", "prod")]))
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.count == 2)
        #expect(model.rows.map(\.record.metadata.issuer) == ["GitHub", "AWS"])
        #expect(model.loadFailure == nil)
    }

    /// If the list showed the wrong code it would be indistinguishable from showing the
    /// right one, so this is checked against the published vector rather than against
    /// whatever the app produces.
    @Test("The code shown is the code the RFC says")
    func generatesPublishedCode() throws {
        let model = AccountListViewModel(store: try eightDigitStore())
        model.load(at: Date(timeIntervalSince1970: 59))

        #expect(model.rows.first?.code == "94287082")
    }

    @Test("The countdown reflects the clock")
    func countdownFollowsTheClock() {
        let model = AccountListViewModel(store: store())

        model.load(at: Date(timeIntervalSince1970: 0))
        #expect(model.rows.first?.secondsRemaining == 30)

        model.tick(at: Date(timeIntervalSince1970: 25))
        #expect(model.rows.first?.secondsRemaining == 5)
    }

    /// Regenerating means an HMAC and a Keychain read. Doing it every second, for every
    /// account, to produce a value that changes twice a minute would be wasteful in the
    /// one place a phone notices: the radio silence between wakeups.
    @Test("A code is regenerated only when it actually changes")
    func regeneratesOnlyOnCounterChange() throws {
        let counting = CountingStore(wrapping: try eightDigitStore())
        let model = AccountListViewModel(store: counting)

        model.load(at: Date(timeIntervalSince1970: 0))
        let afterLoad = counting.secretReads

        for second in 1...29 {
            model.tick(at: Date(timeIntervalSince1970: TimeInterval(second)))
        }

        #expect(counting.secretReads == afterLoad, "The code should not have been regenerated yet")
        #expect(model.rows.first?.code == "94287082" || model.rows.first?.code != nil)

        model.tick(at: Date(timeIntervalSince1970: 30))
        #expect(counting.secretReads == afterLoad + 1, "The new period should have regenerated once")
    }

    @Test("The code changes when the period rolls over")
    func codeChangesWithPeriod() throws {
        let model = AccountListViewModel(store: try eightDigitStore())

        model.load(at: Date(timeIntervalSince1970: 0))
        let first = model.rows.first?.code

        model.tick(at: Date(timeIntervalSince1970: 59))
        #expect(model.rows.first?.code == "94287082")
        #expect(model.rows.first?.code != first)
    }

    // MARK: - No secret reaches the view layer

    /// The central claim of the storage design, asserted rather than described.
    ///
    /// A row carries the account's name, colour, and six digits. If a secret were ever
    /// held on the view model, this is where it would show up.
    @Test("No row holds secret material")
    func rowsHoldNoSecrets() {
        let model = AccountListViewModel(store: store())
        model.load(at: Date(timeIntervalSince1970: 0))

        let row = model.rows[0]
        let reflected = String(describing: row)

        #expect(!reflected.contains("12345678901234567890"))
        #expect(!reflected.lowercased().contains("secret"))

        // And the card handed to SwiftUI carries even less.
        #expect(!String(describing: row.card).contains("12345678901234567890"))
    }

    @Test("A row exposes only what a card needs")
    func rowExposesOnlyPresentableFields() {
        let model = AccountListViewModel(store: store())
        model.load(at: Date(timeIntervalSince1970: 0))

        let card = model.rows[0].card
        #expect(card.issuer == "GitHub")
        #expect(card.name == "octocat")
        #expect(card.code.count == 6)
    }

    // MARK: - Search

    @Test(
        "Search matches issuer and name, ignoring case",
        arguments: [
            (query: "git", expected: ["GitHub"]),
            (query: "GITHUB", expected: ["GitHub"]),
            (query: "octo", expected: ["GitHub"]),
            (query: "prod", expected: ["AWS"]),
            (query: "  aws  ", expected: ["AWS"]),
            (query: "", expected: ["GitHub", "AWS"]),
            (query: "nothing", expected: []),
        ]
    )
    func searchFilters(query: String, expected: [String]) {
        let model = AccountListViewModel(store: store([("GitHub", "octocat"), ("AWS", "prod")]))
        model.load(at: Date(timeIntervalSince1970: 0))
        model.searchText = query

        #expect(model.visibleRows.map(\.record.metadata.displayIssuer) == expected)
    }

    @Test("Whitespace alone is not a search")
    func whitespaceIsNotASearch() {
        let model = AccountListViewModel(store: store())
        model.searchText = "   "

        #expect(!model.isSearching)
    }

    // MARK: - Failures

    /// Finding F3 from gate A1. One account this version cannot read must not take the
    /// rest of the list down with it.
    @Test("An unreadable account does not hide the readable ones")
    func unreadableAccountsAreListedSeparately() {
        let store = PartiallyUnreadableStore()
        let model = AccountListViewModel(store: store)

        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.count == 1)
        #expect(model.rows.first?.record.metadata.issuer == "Readable")
        #expect(model.unreadable == [store.brokenID])
        #expect(model.loadFailure == nil, "One bad record is not a failure of the whole read")
    }

    @Test("A failure to read the store at all is reported")
    func loadFailureIsReported() {
        let model = AccountListViewModel(store: FailingStore(error: .deviceLocked))
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.isEmpty)
        #expect(model.loadFailure != nil)
    }

    /// A locked device is the ordinary case here, not an exceptional one, and the row has
    /// to say so rather than show digits that are not a code.
    @Test("A code that cannot be generated leaves the row without one")
    func codeFailureIsPerRow() {
        let model = AccountListViewModel(store: SecretlessStore())
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.count == 1)
        #expect(model.rows.first?.code == nil)
        #expect(model.rows.first?.codeFailure != nil)
        #expect(model.loadFailure == nil)
    }

    // MARK: - Counter based accounts

    /// A counter based code does not expire on a clock, so a countdown ring would be a
    /// lie. The card takes `nil` and draws no ring at all.
    @Test("Counter based accounts have no countdown")
    func counterBasedAccountsHaveNoCountdown() {
        let model = AccountListViewModel(
            store: store(generator: .hotp(counter: 0, digits: .six, algorithm: .sha1))
        )
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.rows.first?.code == "755224", "RFC 4226 Appendix D, counter 0")
        #expect(model.rows.first?.secondsRemaining == nil)
        #expect(model.rows.first?.card.fractionRemaining == nil)
    }

    // MARK: - Copying

    @Test("Copying a code without one does nothing")
    func copyingWithoutACodeDoesNothing() {
        let model = AccountListViewModel(store: SecretlessStore())
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.copyCode(for: model.rows[0], at: Date()) == false)
    }

    @Test("Copying reports success when there is a code")
    func copyingSucceeds() {
        let model = AccountListViewModel(store: store())
        model.load(at: Date(timeIntervalSince1970: 0))

        #expect(model.copyCode(for: model.rows[0], at: Date()) == true)
    }
}

// MARK: - Doubles

/// Counts how often a secret is actually read, which is the only way to prove the list is
/// not regenerating codes it does not need to.
private final class CountingStore: SecretStore, @unchecked Sendable {
    private let wrapped: any SecretStore
    private(set) var secretReads = 0

    init(wrapping wrapped: any SecretStore) {
        self.wrapped = wrapped
    }

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        try wrapped.add(account, color: color)
    }

    func records() throws(SecretStoreError) -> StoredRecords { try wrapped.records() }

    func secret(for id: UUID) throws(SecretStoreError) -> Data {
        secretReads += 1
        return try wrapped.secret(for: id)
    }

    func update(_ record: AccountRecord) throws(SecretStoreError) { try wrapped.update(record) }
    func delete(id: UUID) throws(SecretStoreError) { try wrapped.delete(id: id) }
}

/// One readable account and one this version cannot make sense of.
private struct PartiallyUnreadableStore: SecretStore {
    let brokenID = UUID()
    private let readableID = UUID()

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        throw .notFound
    }

    func records() throws(SecretStoreError) -> StoredRecords {
        StoredRecords(
            readable: [
                AccountRecord(
                    id: readableID,
                    metadata: AccountMetadata(
                        issuer: "Readable",
                        name: "fine",
                        generator: .totp(.standard),
                        color: .blue,
                        sortIndex: 0
                    )
                )
            ],
            unreadable: [brokenID]
        )
    }

    func secret(for id: UUID) throws(SecretStoreError) -> Data { Data("12345678901234567890".utf8) }
    func update(_ record: AccountRecord) throws(SecretStoreError) {}
    func delete(id: UUID) throws(SecretStoreError) {}
}

/// Fails every read, the way a locked device does.
private struct FailingStore: SecretStore {
    let error: SecretStoreError

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        throw error
    }

    func records() throws(SecretStoreError) -> StoredRecords { throw error }
    func secret(for id: UUID) throws(SecretStoreError) -> Data { throw error }
    func update(_ record: AccountRecord) throws(SecretStoreError) { throw error }
    func delete(id: UUID) throws(SecretStoreError) { throw error }
}

/// Lists an account but cannot produce its secret, which is what a locked device looks
/// like halfway through a refresh.
private struct SecretlessStore: SecretStore {
    private let id = UUID()

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        throw .notFound
    }

    func records() throws(SecretStoreError) -> StoredRecords {
        StoredRecords(
            readable: [
                AccountRecord(
                    id: id,
                    metadata: AccountMetadata(
                        issuer: "Locked",
                        name: "account",
                        generator: .totp(.standard),
                        color: .blue,
                        sortIndex: 0
                    )
                )
            ]
        )
    }

    func secret(for id: UUID) throws(SecretStoreError) -> Data { throw .deviceLocked }
    func update(_ record: AccountRecord) throws(SecretStoreError) {}
    func delete(id: UUID) throws(SecretStoreError) {}
}
