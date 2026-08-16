import Foundation
import Testing

@testable import OpenFactorCore

/// The signal a device uses to decide its vault key is the wrong one.
///
/// Three lines of logic that decide whether a device discards a key and asks for another, which
/// is reason enough for them to be somewhere a test can reach. They were written inside a watch
/// view model first, where nothing could.
@Suite("A key that opens nothing")
struct WrongKeySignalTests {

    private func record(_ name: String) -> AccountRecord {
        AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: "Example",
                name: name,
                generator: .totp(.standard),
                color: .blue,
                sortIndex: 0))
    }

    @Test("Records present and none of them readable is the signal")
    func allUnreadable() {
        let records = StoredRecords(readable: [], unreadable: [UUID(), UUID()])
        #expect(records.suggestsAWrongKey)
    }

    /// The case that would make a device throw its key away every time it got ahead of iCloud.
    @Test("An empty store is not a wrong key")
    func emptyIsNotASignal() {
        #expect(!StoredRecords(readable: [], unreadable: []).suggestsAWrongKey)
    }

    /// What `unreadable` was invented for, and it has nothing to do with keys.
    @Test("A mixture is a newer version's record, not a wrong key")
    func mixtureIsNotASignal() {
        let records = StoredRecords(readable: [record("one")], unreadable: [UUID()])
        #expect(!records.suggestsAWrongKey)
    }

    @Test("A store that reads perfectly is not a wrong key")
    func allReadableIsNotASignal() {
        let records = StoredRecords(readable: [record("one"), record("two")])
        #expect(!records.suggestsAWrongKey)
    }
}
