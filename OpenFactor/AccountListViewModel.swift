import Foundation
import OpenFactorCore

/// Everything the account list needs to draw itself, and nothing else.
///
/// Three rules this type exists to hold, all of them security decisions rather than
/// architectural taste:
///
/// **No secret material is ever stored here.** A row holds an account's name, colour, and
/// its current six digits. The secret is read from the Keychain inside
/// ``refreshCode(for:at:)``, used, and dropped in the same expression. Nothing in this
/// object outlives it, which is why `AccountListViewModelTests` asserts on the type's
/// stored properties rather than trusting this paragraph.
///
/// **One tick drives the whole list.** ``tick(at:)`` is called once a second by the view.
/// A timer per row would be ten timers for ten accounts, waking the CPU ten times as often
/// for the same result.
///
/// **A code is only regenerated when it actually changes.** Ticking updates the countdown,
/// which is arithmetic, but recomputing the code means an HMAC and a Keychain read, so it
/// happens once per period per account rather than once a second per account.
///
/// The clock is a parameter, as it is everywhere else in this project, so the tests drive
/// time rather than wait for it.
@MainActor
@Observable
final class AccountListViewModel {

    /// One account, as the list sees it.
    struct Row: Identifiable, Equatable {
        let record: AccountRecord

        /// The current code, or `nil` if it could not be generated.
        var code: String?

        /// Why the code is missing. Shown on the card in place of the digits.
        var codeFailure: String?

        var secondsRemaining: TimeInterval?

        /// The counter the current code was generated for, so a tick can tell whether
        /// anything needs regenerating.
        fileprivate var generatedCounter: UInt64?

        var id: UUID { record.id }

        var card: AccountCard.Model {
            AccountCard.Model(
                issuer: record.metadata.displayIssuer,
                name: record.metadata.name,
                code: code ?? "------",
                secondsRemaining: secondsRemaining,
                period: period,
                color: record.metadata.color
            )
        }

        var period: Int {
            switch record.metadata.generator {
            case let .totp(configuration): configuration.period
            case .hotp: 0
            }
        }

        var isTimeBased: Bool {
            if case .totp = record.metadata.generator { true } else { false }
        }
    }

    // MARK: - State

    private(set) var rows: [Row] = []

    /// Accounts that exist but that this version cannot read. See ``StoredRecords``.
    private(set) var unreadable: [UUID] = []

    /// Set only when the whole read failed, which is a different thing from one account
    /// failing and is shown differently.
    private(set) var loadFailure: String?

    var searchText: String = ""

    /// The rows actually shown, after the search field.
    var visibleRows: [Row] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }

        return rows.filter { row in
            row.record.metadata.displayIssuer.localizedCaseInsensitiveContains(query)
                || row.record.metadata.name.localizedCaseInsensitiveContains(query)
        }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
    }

    // MARK: - Loading

    /// Reads the account list. Decrypts no secrets: see `KeychainSecretStore.records()`.
    func load(at date: Date) {
        do {
            let stored = try store.records()

            // Existing rows are matched by identifier so a reload does not blank every
            // code and make the list flash.
            let existing = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            rows = stored.readable.map { record in
                var row = existing[record.id] ?? Row(record: record)
                row = Row(
                    record: record,
                    code: row.code,
                    codeFailure: row.codeFailure,
                    secondsRemaining: row.secondsRemaining,
                    generatedCounter: row.generatedCounter
                )
                return row
            }

            unreadable = stored.unreadable
            loadFailure = nil
        } catch {
            rows = []
            unreadable = []
            loadFailure = error.description
        }

        tick(at: date)
    }

    // MARK: - Ticking

    /// Advances every visible countdown, and regenerates the codes that have expired.
    ///
    /// Called once a second by the view, from a single timer.
    func tick(at date: Date) {
        for index in rows.indices {
            let period = rows[index].period

            guard rows[index].isTimeBased, period > 0 else {
                // Counter based. Generate once, then leave it alone: its code changes when
                // the user asks for the next one, which arrives with the rest of the
                // counter based support in a later pull request.
                if rows[index].code == nil && rows[index].codeFailure == nil {
                    refreshCode(at: index, date: date, counter: nil)
                }
                continue
            }

            rows[index].secondsRemaining = TOTP.timeRemaining(at: date, period: period)

            let counter = TOTP.counter(at: date, period: period)
            if rows[index].generatedCounter != counter {
                refreshCode(at: index, date: date, counter: counter)
            }
        }
    }

    /// Reads one secret, generates one code, and keeps neither.
    ///
    /// `store.code(for:at:)` reads the secret, uses it, and lets it go inside that call.
    /// The secret never reaches a property of this object.
    private func refreshCode(at index: Int, date: Date, counter: UInt64?) {
        do {
            rows[index].code = try store.code(for: rows[index].record, at: date)
            rows[index].codeFailure = nil
            rows[index].generatedCounter = counter
        } catch {
            rows[index].code = nil
            rows[index].generatedCounter = nil
            rows[index].codeFailure = error.description
        }
    }

    // MARK: - Copying

    /// Puts a code on the pasteboard, briefly.
    ///
    /// Returns whether anything was copied, so the view knows whether to confirm.
    @discardableResult
    func copyCode(for row: Row, at date: Date) -> Bool {
        guard let code = row.code else { return false }

        // The clipboard entry dies with the code it holds. A 2FA code that outlives its
        // own validity is pure liability sitting in a place other apps can read.
        let expiry =
            row.isTimeBased && row.period > 0
            ? TOTP.expiry(at: date, period: row.period)
            : date.addingTimeInterval(30)

        CodeClipboard.copy(code, expiring: expiry)
        return true
    }
}
