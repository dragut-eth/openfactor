import Foundation

/// What came back from a read of the store.
///
/// Two lists rather than one, because "this account cannot be read" is information the
/// user needs and not a reason to show them nothing.
///
/// Before this existed, one record whose metadata could not be decoded failed the whole
/// read, so a single unreadable account made every other account invisible. That was
/// recorded as finding F3 at gate A1 and deferred to here, because reporting it properly
/// needs an interface to report it in. See `docs/audits/A1.md`.
///
/// The alternative, quietly skipping records that cannot be read, is worse than either.
/// An account that vanishes without a word is an account the user believes they have lost,
/// and its secret is still sitting in the Keychain intact.
public struct StoredRecords: Sendable, Equatable {

    /// Accounts that can be shown, sorted.
    public let readable: [AccountRecord]

    /// Accounts that exist and whose metadata this version cannot make sense of.
    ///
    /// Almost always means the record was written by a newer version of the app that
    /// added something to the format. The secret is untouched, so an older version showing
    /// a placeholder and a newer one showing the account are both correct.
    public let unreadable: [UUID]

    public init(readable: [AccountRecord], unreadable: [UUID] = []) {
        self.readable = readable
        self.unreadable = unreadable
    }

    public var isEmpty: Bool {
        readable.isEmpty && unreadable.isEmpty
    }
}
