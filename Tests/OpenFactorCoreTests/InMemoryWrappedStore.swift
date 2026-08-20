import Foundation

@testable import OpenFactorCore

/// A wrapped-record store that keeps its record in memory and can be told to fail.
///
/// **This exists because the Keychain is unavailable to this package's tests**, which means the
/// `Vault lifecycle` suite is skipped on the machine that runs the suite. Every decision the
/// vault makes, including the two that destroy accounts when they are wrong, was therefore
/// unverified. `WrappedRecordStore` says the rest.
///
/// A class rather than a struct, because a test needs to see what the vault wrote through a value
/// it handed away.
final class InMemoryWrappedStore: WrappedRecordStore, @unchecked Sendable {

    private let lock = NSLock()
    private var records: [WrappedCandidate] = []

    /// When set, every read fails with it. This is the state that used to be indistinguishable
    /// from an empty store, and being able to reach it is the point of this type.
    var readFailure: SecretStoreError?

    init(record: Data? = nil) {
        records = record.map { [WrappedCandidate(record: $0, isSynchronizable: false)] } ?? []
    }

    var storedRecord: Data? {
        lock.withLock { records.first?.record }
    }

    /// Plants a second record carrying the opposite flag, which is the twin case S1-12 is about
    /// and which no test could express while this held one optional value.
    func plantTwin(_ record: Data, isSynchronizable: Bool) {
        lock.withLock {
            records.append(WrappedCandidate(record: record, isSynchronizable: isSynchronizable))
        }
    }

    var recordCount: Int { lock.withLock { records.count } }

    func candidates() throws(SecretStoreError) -> [WrappedCandidate] {
        if let readFailure { throw readFailure }
        return lock.withLock { records }
    }

    func load() throws(SecretStoreError) -> Data? {
        if let readFailure { throw readFailure }
        return lock.withLock { records.first?.record }
    }

    /// Runs immediately before a creation write commits, so a test can do what iCloud does:
    /// deliver a record while the key derivation is still running.
    ///
    /// **The suite could not express that until this existed**, which is why round two's finding
    /// was green against the test written for it: the fake's record never changed between the
    /// check and the write, so a check made hundreds of milliseconds early looked the same as a
    /// check made at the right moment.
    var duringWrite: (@Sendable () -> Void)?

    /// When set, every write fails with it.
    ///
    /// **Added because a review named its absence as the most consequential unverified decision
    /// left in this scope.** Without it, nothing could check what happens when the record cannot
    /// be written, and the record-before-key ordering is the whole of the recovery story: a key
    /// with no record is a device that works until it is replaced and then cannot be recovered by
    /// anybody.
    var writeFailure: SecretStoreError?

    /// Mirrors the Keychain implementation's twin refusal rather than collapsing the pair.
    ///
    /// The first version of this fake replaced every record with one, so the decision `save`
    /// now makes when two exist, refuse rather than update one unspecified, was inexpressible
    /// here and its coverage was an illusion. Round four filed that as its own finding.
    func save(_ record: Data) throws(SecretStoreError) {
        if let writeFailure { throw writeFailure }
        lock.lock()
        defer { lock.unlock() }
        guard records.count <= 1 else { throw .twinnedRecord }
        let flag = records.first?.isSynchronizable ?? false
        records = [WrappedCandidate(record: record, isSynchronizable: flag)]
    }

    func addIfAbsent(_ record: Data) throws(SecretStoreError) -> Bool {
        if let writeFailure { throw writeFailure }
        duringWrite?()
        return lock.withLock {
            guard records.isEmpty else { return false }
            records = [WrappedCandidate(record: record, isSynchronizable: false)]
            return true
        }
    }

    func delete() throws(SecretStoreError) {
        lock.withLock { records = [] }
    }
}
