import Foundation
import OpenFactorCore
import Testing

@testable import OpenFactor

/// Editing must never disturb the parts of an account that make its codes correct. The
/// name and colour are labels a person chose; the secret and the generator settings came
/// from the service and changing them would silently stop the codes matching.
@MainActor
@Suite("Editing accounts")
struct EditAccountTests {

    private static let secret = Data("12345678901234567890".utf8)

    private func loadedModel(
        _ accounts: [(issuer: String, name: String, color: AccountColor)] = [
            ("GitHub", "octocat", .blue)
        ]
    ) throws -> (AccountListViewModel, InMemorySecretStore) {
        let store = InMemorySecretStore()

        for account in accounts {
            try store.add(
                OTPAccount(
                    issuer: account.issuer,
                    name: account.name,
                    secret: Self.secret,
                    generator: .totp(.standard)
                ),
                color: account.color
            )
        }

        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))
        return (model, store)
    }

    // MARK: - Renaming

    @Test("Renaming changes the labels and persists")
    func renamePersists() throws {
        let (model, store) = try loadedModel()

        model.rename(try #require(model.rows.first), issuer: "GitLab", name: "someone-else")

        #expect(model.rows.first?.record.metadata.issuer == "GitLab")
        #expect(model.rows.first?.record.metadata.name == "someone-else")

        let stored = try #require(try store.records().readable.first)
        #expect(stored.metadata.issuer == "GitLab")
        #expect(stored.metadata.name == "someone-else")
    }

    /// The whole point of the constraint: a rename must not be able to change the codes.
    @Test("Renaming leaves the secret and the generator alone")
    func renameDoesNotTouchTheCode() throws {
        let (model, store) = try loadedModel()
        let row = try #require(model.rows.first)
        let codeBefore = row.code

        model.rename(row, issuer: "Something Else", name: "renamed")

        #expect(try store.secret(for: row.id) == Self.secret)
        #expect(model.rows.first?.record.metadata.generator == .totp(.standard))
        #expect(model.rows.first?.code == codeBefore, "A rename must not blank or change the code")
    }

    @Test("An emptied issuer becomes no issuer rather than an empty one")
    func emptyIssuerBecomesNil() throws {
        let (model, _) = try loadedModel()

        model.rename(try #require(model.rows.first), issuer: "   ", name: "octocat")

        #expect(model.rows.first?.record.metadata.issuer == nil)
    }

    @Test("Names are trimmed on the way in")
    func namesAreTrimmed() throws {
        let (model, _) = try loadedModel()

        model.rename(try #require(model.rows.first), issuer: "  GitHub  ", name: "  octocat  ")

        #expect(model.rows.first?.record.metadata.issuer == "GitHub")
        #expect(model.rows.first?.record.metadata.name == "octocat")
    }

    // MARK: - Colour

    @Test("Changing the colour persists and leaves everything else alone")
    func colourPersists() throws {
        let (model, store) = try loadedModel()
        let row = try #require(model.rows.first)

        model.setColor(.pink, for: row)

        #expect(model.rows.first?.record.metadata.color == .pink)
        #expect(try store.records().readable.first?.metadata.color == .pink)
        #expect(model.rows.first?.record.metadata.name == "octocat")
        #expect(model.rows.first?.code != nil)
    }

    // MARK: - Deleting

    @Test("Deleting removes the account and its secret")
    func deleteRemovesEverything() throws {
        let (model, store) = try loadedModel([
            ("GitHub", "octocat", .blue),
            ("AWS", "prod", .yellow),
        ])
        let row = try #require(model.rows.first)

        model.delete(row)

        #expect(model.rows.map(\.record.metadata.issuer) == ["AWS"])
        #expect(try store.records().readable.count == 1)
        #expect(throws: SecretStoreError.notFound) {
            try store.secret(for: row.id)
        }
    }

    // MARK: - Reordering

    @Test("Moving a row reorders the list and persists the new order")
    func moveReordersAndPersists() throws {
        let (model, store) = try loadedModel([
            ("First", "a", .red),
            ("Second", "b", .green),
            ("Third", "c", .blue),
        ])

        // Drag the last card to the top.
        model.move(from: IndexSet(integer: 2), to: 0)

        #expect(model.rows.map(\.record.metadata.issuer) == ["Third", "First", "Second"])

        // The order has to survive a reload, or it was only ever on screen.
        let reloaded = AccountListViewModel(store: store)
        reloaded.load(at: Date(timeIntervalSince1970: 0))
        #expect(reloaded.rows.map(\.record.metadata.issuer) == ["Third", "First", "Second"])
    }

    @Test("Sort positions come out contiguous after a move")
    func moveProducesContiguousPositions() throws {
        let (model, _) = try loadedModel([
            ("First", "a", .red),
            ("Second", "b", .green),
            ("Third", "c", .blue),
        ])

        model.move(from: IndexSet(integer: 0), to: 3)

        #expect(model.rows.map(\.record.metadata.sortIndex) == [0, 1, 2])
    }

    /// Each write is a Keychain round trip, so dragging one card should not rewrite the
    /// whole list.
    @Test("Only the rows that actually moved are written")
    func moveWritesOnlyWhatChanged() throws {
        let store = CountingUpdateStore()
        for issuer in ["First", "Second", "Third", "Fourth"] {
            try store.add(
                OTPAccount(issuer: issuer, name: "x", secret: Self.secret, generator: .totp(.standard)),
                color: .blue
            )
        }

        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))
        store.updates = 0

        // Swapping the first two leaves the last two where they are.
        model.move(from: IndexSet(integer: 0), to: 2)

        #expect(store.updates == 2, "Only the two rows that changed position should be written")
    }

    @Test("Moving keeps the codes on screen")
    func moveKeepsCodes() throws {
        let (model, _) = try loadedModel([
            ("First", "a", .red),
            ("Second", "b", .green),
        ])
        let codes = model.rows.compactMap(\.code)

        model.move(from: IndexSet(integer: 0), to: 2)

        #expect(model.rows.compactMap(\.code).count == codes.count)
        #expect(model.rows.allSatisfy { $0.code != nil })
    }
}

/// Counts metadata writes, so a test can prove the list is not rewriting rows it did not
/// need to touch.
private final class CountingUpdateStore: SecretStore, @unchecked Sendable {
    private let wrapped = InMemorySecretStore()
    var updates = 0

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        try wrapped.add(account, color: color)
    }

    func records() throws(SecretStoreError) -> StoredRecords { try wrapped.records() }
    func secret(for id: UUID) throws(SecretStoreError) -> Data { try wrapped.secret(for: id) }
    func delete(id: UUID) throws(SecretStoreError) { try wrapped.delete(id: id) }

    func update(_ record: AccountRecord) throws(SecretStoreError) {
        updates += 1
        try wrapped.update(record)
    }
}
