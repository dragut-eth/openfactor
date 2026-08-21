import Foundation
import Testing

@testable import OpenFactorCore

/// The gates in front of erasing every account.
///
/// **Nothing tested these until a reviewer said so.** `docs/MASVS.md` scored MASVS-AUTH-3 as a
/// pass and cited `EraseAccountsTests`, which proves that deleting deletes. It proved nothing
/// about the Face ID check or the typed word, because both lived in a SwiftUI view where no test
/// could reach them. The verdict was resting on prose, which is precisely what that document's
/// own evidence rule forbids.
///
/// **The ordering is the property**, not the two checks separately. Everything below is written
/// so that reversing the order, or dropping either gate, reddens something by name.
@Suite("Erase gate")
struct EraseGateTests {

    private func storeWithAccounts(_ count: Int) throws -> InMemorySecretStore {
        let store = InMemorySecretStore()
        for index in 0..<count {
            _ = try store.add(
                OTPAccount(
                    issuer: "Issuer \(index)",
                    name: "name-\(index)",
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)),
                color: .blue)
        }
        return store
    }

    // MARK: - The typed word

    @Test("The word is ERASE, and it is not delete")
    func theWordIsPinned() {
        #expect(EraseGate.confirmation == "ERASE")
        #expect(!EraseGate.isConfirmed("DELETE"))
    }

    @Test(
        "Accepted spellings",
        arguments: ["ERASE", "erase", "Erase", " ERASE ", "erase\n"])
    func accepted(_ typed: String) {
        #expect(EraseGate.isConfirmed(typed))
    }

    @Test(
        "Refused spellings",
        arguments: ["", " ", "ERAS", "ERASEE", "ER ASE", "supprimer"])
    func refused(_ typed: String) {
        #expect(!EraseGate.isConfirmed(typed))
    }

    // MARK: - The two gates, and the order they run in

    /// **The whole point of the extraction.** A test bundle cannot make a real Face ID prompt
    /// fail, so this path was unreachable while the call was made inside the view.
    @Test("A refused identity check erases nothing")
    func refusedIdentityErasesNothing() async throws {
        let store = try storeWithAccounts(3)

        let outcome = await EraseGate.erase(typed: "ERASE", from: store) { false }

        #expect(outcome == .notAuthenticated)
        #expect(try store.records().readable.count == 3, "every account must still be there")
    }

    /// **Authentication must not run before the word is typed.** Prompting for Face ID and then
    /// refusing on the word would train somebody to authenticate their way into a screen that
    /// was never going to act, which is how a confirmation stops being read.
    @Test("The word is checked before identity is even asked for")
    func wordIsCheckedFirst() async throws {
        let store = try storeWithAccounts(2)
        var asked = false

        let outcome = await EraseGate.erase(typed: "nope", from: store) {
            asked = true
            return true
        }

        #expect(outcome == .notConfirmed)
        #expect(!asked, "identity must not be requested for a confirmation that already failed")
        #expect(try store.records().readable.count == 2)
    }

    @Test("Both gates passed erases every account")
    func bothGatesPassed() async throws {
        let store = try storeWithAccounts(4)

        let outcome = await EraseGate.erase(typed: "ERASE", from: store) { true }

        #expect(outcome == .erased(4))
        #expect(try store.records().readable.isEmpty)
    }

    /// **Records this version cannot decode are erased too.** Leaving them is the worst outcome
    /// available on this screen: an erase that reports success and leaves secrets on the device.
    ///
    /// Remove `records.unreadable` from the identifiers and this goes red.
    @Test("Unreadable records are erased as well as readable ones")
    func unreadableRecordsAreErasedToo() async throws {
        let store = StoreWithAStrandedRecord()
        #expect(try store.records().unreadable.count == 1)

        let outcome = await EraseGate.erase(typed: "ERASE", from: store) { true }

        #expect(outcome == .erased(3), "two readable and one unreadable")
        let after = try store.records()
        #expect(after.readable.isEmpty)
        #expect(after.unreadable.isEmpty, "a record nobody can read is still a secret")
    }

    @Test("An empty store is erased without complaint")
    func emptyStore() async {
        let outcome = await EraseGate.erase(typed: "ERASE", from: InMemorySecretStore()) { true }
        #expect(outcome == .erased(0))
    }
}

/// A store holding one record this version cannot decode.
///
/// **Written here rather than added to `InMemorySecretStore` as a seam.** The in-memory store
/// ships, and a hook that exists only so a test can reach a state is the shape that produced
/// S1-38 and two of the four non-discriminating tests this gate found. This fake is the whole
/// behaviour, visible in one place.
private final class StoreWithAStrandedRecord: SecretStore, @unchecked Sendable {

    private var readable: [AccountRecord]
    private var unreadable: [UUID]

    init() {
        let inMemory = InMemorySecretStore()
        readable = (0..<2).compactMap { index in
            try? inMemory.add(
                OTPAccount(
                    issuer: "Issuer \(index)",
                    name: "name-\(index)",
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)),
                color: .blue)
        }
        unreadable = [UUID()]
    }

    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord {
        throw .notFound
    }

    func records() throws(SecretStoreError) -> StoredRecords {
        StoredRecords(readable: readable, unreadable: unreadable)
    }

    func secret(for id: UUID) throws(SecretStoreError) -> Data {
        throw .notFound
    }

    func update(_ record: AccountRecord) throws(SecretStoreError) {
        throw .notFound
    }

    func delete(id: UUID) throws(SecretStoreError) {
        if let index = readable.firstIndex(where: { $0.id == id }) {
            readable.remove(at: index)
            return
        }
        if let index = unreadable.firstIndex(of: id) {
            unreadable.remove(at: index)
            return
        }
        throw .notFound
    }
}
