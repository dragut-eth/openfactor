import Foundation
import OpenFactorCore
import SwiftUI
import Testing

@testable import OpenFactor

@MainActor
@Suite("Sorting the list")
struct AccountSortOrderTests {

    private func loadedModel() throws -> AccountListViewModel {
        let store = InMemorySecretStore()

        // Added in an order that is none of the sort orders, so a passing test cannot be
        // an accident of insertion order.
        for (issuer, name) in [
            ("Okta", "zoe@example.com"),
            ("aws", "Production"),
            ("GitHub", "alice@example.com"),
            ("aws", "Staging"),
        ] {
            try store.add(
                OTPAccount(
                    issuer: issuer,
                    name: name,
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)
                ),
                color: .blue
            )
        }

        let model = AccountListViewModel(store: store)
        model.load(at: Date(timeIntervalSince1970: 0))
        return model
    }

    /// Manual is the stored order, which is the order accounts were added in until
    /// somebody drags one.
    @Test("Manual keeps the order the accounts are stored in")
    func manualKeepsStoredOrder() throws {
        let model = try loadedModel()
        model.sortOrder = .manual

        #expect(model.visibleRows.map(\.record.metadata.name) == [
            "zoe@example.com", "Production", "alice@example.com", "Staging",
        ])
    }

    /// Case insensitive, or `aws` sorts after `Okta` and the list looks broken to anyone
    /// who does not know about ASCII.
    @Test("By service sorts case insensitively, with the account name breaking ties")
    func sortsByIssuer() throws {
        let model = try loadedModel()
        model.sortOrder = .issuer

        #expect(model.visibleRows.map(\.record.metadata.displayIssuer) == [
            "aws", "aws", "GitHub", "Okta",
        ])
        // Two accounts at the same service is common, so the tie break is not decoration.
        #expect(model.visibleRows.prefix(2).map(\.record.metadata.name) == ["Production", "Staging"])
    }

    @Test("By account sorts on the account name")
    func sortsByName() throws {
        let model = try loadedModel()
        model.sortOrder = .name

        #expect(model.visibleRows.map(\.record.metadata.name) == [
            "alice@example.com", "Production", "Staging", "zoe@example.com",
        ])
    }

    /// Sorting is a view of the list, not a rewrite of it. Switching away and back has to
    /// return the arrangement someone made by hand.
    @Test("An automatic sort does not destroy the manual order")
    func automaticSortLeavesStoredOrderAlone() throws {
        let model = try loadedModel()
        let manual = model.visibleRows.map(\.record.metadata.name)

        model.sortOrder = .name
        _ = model.visibleRows
        model.sortOrder = .manual

        #expect(model.visibleRows.map(\.record.metadata.name) == manual)
        #expect(model.rows.map(\.record.metadata.sortIndex) == [0, 1, 2, 3])
    }

    @Test("Search and sort apply together")
    func searchAndSortCompose() throws {
        let model = try loadedModel()
        model.sortOrder = .name
        model.searchText = "aws"

        #expect(model.visibleRows.map(\.record.metadata.name) == ["Production", "Staging"])
    }

    // MARK: - Reordering

    /// Rearranging a list that is only half shown is not a coherent gesture. An automatic
    /// sort is not a reason to refuse, see below.
    @Test("Reordering is offered whenever the whole list is on screen")
    func reorderingRequiresTheWholeList() throws {
        let model = try loadedModel()

        model.sortOrder = .manual
        #expect(model.canReorder)

        model.sortOrder = .issuer
        #expect(model.canReorder)

        model.searchText = "aws"
        #expect(!model.canReorder, "A list that is half hidden cannot be rearranged coherently")
    }

    /// Refusing the gesture is the worst option: the user has said plainly where they want
    /// the card. Taking the order they are looking at, making it theirs, and then moving
    /// the card within it is the only reading that respects what they did.
    @Test("Dragging a sorted list adopts the order it is showing")
    func draggingAdoptsTheVisibleOrder() throws {
        let model = try loadedModel()
        model.sortOrder = .name

        var persisted: AccountSortOrder?
        model.onSortOrderChange = { persisted = $0 }

        let shown = model.visibleRows.map(\.record.metadata.name)
        #expect(shown == ["alice@example.com", "Production", "Staging", "zoe@example.com"])

        // Drag the last card to the top.
        model.move(from: IndexSet(integer: 3), to: 0)

        #expect(model.sortOrder == .manual)
        #expect(persisted == .manual, "The switch has to be written back, or it reverts on relaunch")
        #expect(model.visibleRows.map(\.record.metadata.name) == [
            "zoe@example.com", "alice@example.com", "Production", "Staging",
        ])
    }

    /// The point of adopting the visible order: the positions written must be the ones the
    /// user was looking at, not the stored ones the sort was hiding.
    @Test("The adopted order is the one that was on screen, and it survives a reload")
    func adoptedOrderPersists() throws {
        let model = try loadedModel()
        model.sortOrder = .issuer

        let shown = model.visibleRows.map(\.record.metadata.name)
        model.move(from: IndexSet(integer: 0), to: 1)

        var expected = shown
        expected.move(fromOffsets: IndexSet(integer: 0), toOffset: 1)

        #expect(model.visibleRows.map(\.record.metadata.name) == expected)
        #expect(model.rows.map(\.record.metadata.sortIndex) == [0, 1, 2, 3])
    }
}

@Suite("Preferences")
struct PreferencesTests {

    /// Both preferences are read from storage as raw strings, so an unrecognised value has
    /// to land somewhere sensible rather than crash or blank the screen.
    @Test("An unknown stored value falls back to the default")
    func unknownValuesFallBack() {
        #expect(AccountSortOrder(rawValue: "byVibes") == nil)
        #expect(AppearancePreference(rawValue: "sepia") == nil)
    }

    @Test("System appearance means following the system")
    func systemAppearanceFollowsTheSystem() {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.light.colorScheme == .light)
        #expect(AppearancePreference.dark.colorScheme == .dark)
    }

    @Test("Every option has a label")
    func everyOptionIsLabelled() {
        for order in AccountSortOrder.allCases {
            #expect(!order.label.isEmpty)
        }
        for appearance in AppearancePreference.allCases {
            #expect(!appearance.label.isEmpty)
        }
    }
}
