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
    private var record: Data?

    /// When set, every read fails with it. This is the state that used to be indistinguishable
    /// from an empty store, and being able to reach it is the point of this type.
    var readFailure: SecretStoreError?

    init(record: Data? = nil) {
        self.record = record
    }

    var storedRecord: Data? {
        lock.withLock { record }
    }

    func load() throws(SecretStoreError) -> Data? {
        if let readFailure { throw readFailure }
        return lock.withLock { record }
    }

    func save(_ record: Data) throws(SecretStoreError) {
        lock.withLock { self.record = record }
    }

    func delete() throws(SecretStoreError) {
        lock.withLock { record = nil }
    }
}
