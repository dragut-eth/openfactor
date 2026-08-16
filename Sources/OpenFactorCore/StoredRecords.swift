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

    /// **Records are here and not one of them opens**, which is what a device holding the wrong
    /// vault key looks like from the outside.
    ///
    /// It happens for real: replace the vault on a phone, which is what erasing everything and
    /// setting up again does, and a watch provisioned earlier keeps the old key while every
    /// record that arrives is sealed under the new one. Having a key is not the same as having
    /// the right one, and a device that only checks for presence reports zero accounts, which is
    /// true and useless and offers no way back.
    ///
    /// **Both halves of the condition are load bearing.** No records at all is an empty vault or
    /// one still arriving, and must not be read as a wrong key: a device that threw its key away
    /// on an empty read would do so every time it got ahead of iCloud. A mixture is a record
    /// written by a newer version sitting beside ones this build understands, which is the case
    /// `unreadable` was invented for and has nothing to do with keys.
    ///
    /// A signal rather than a proof. The only certain reading is that this build cannot open
    /// anything it can see, so a caller may re-provision **once** and must then believe the
    /// second answer. `WatchVaultModel` does exactly that.
    public var suggestsAWrongKey: Bool {
        readable.isEmpty && !unreadable.isEmpty
    }
}
