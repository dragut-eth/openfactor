import OpenFactorCore

/// Which accounts the watch can finish, and the order it puts them in.
///
/// **Counter based accounts are shown, not hidden.** The watch is read only and advancing a
/// counter is a write, so it genuinely cannot produce those codes. Dropping them from the
/// list would be the tidier screen and the worse app: on a watch, absent is
/// indistinguishable from not synced yet, and this project has already spent half an hour
/// convinced sync was broken when iCloud Keychain was merely slow. A wearer counting four
/// rows against seven accounts on their phone would have no way to tell a design decision
/// from a bug.
///
/// The failure case that settles it is a person whose accounts are *all* counter based.
/// Hide them and the watch says "No accounts yet", which is false, and the empty state
/// written for accounts still in flight starts lying to somebody whose sync works.
///
/// So they are kept, sorted below the ones that work here, and drawn dimmed with a phone
/// glyph. The glanceable set is at the top, the list still accounts for everything on the
/// phone, and a row says what it is before it is tapped rather than after.
enum WatchList {

    /// True when this account's code can only be advanced on the phone.
    static func needsPhone(_ record: AccountRecord) -> Bool {
        if case .totp = record.metadata.generator { return false }
        return true
    }

    /// Time based first, counter based after, each group in the order it arrived.
    ///
    /// Two filters rather than a sort, because a comparator over a boolean is only stable
    /// if the sort is, and the wearer's own ordering inside each group is the thing being
    /// preserved.
    static func ordered(_ records: [AccountRecord]) -> [AccountRecord] {
        records.filter { !needsPhone($0) } + records.filter { needsPhone($0) }
    }
}
