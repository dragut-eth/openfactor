import Foundation

/// A store that keeps everything in memory and touches no Keychain.
///
/// Exists for two reasons: SwiftUI previews need accounts to draw without writing to the
/// device, and the behaviour tests need a store they can run anywhere. It is part of the
/// shipping library rather than the test bundle so that previews can use it, which is a
/// deliberate trade: a few dozen lines of dead weight in the binary in exchange for a
/// preview that cannot accidentally scribble on someone's real accounts.
///
/// It stores secrets in a dictionary in memory. That is not a weakness to fix, it is what
/// the type is for, and nothing in the app ever constructs one. If a future change makes
/// the app construct one, that is the bug.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {

    private struct Entry {
        var metadata: AccountMetadata
        var secret: Data
    }

    /// `@unchecked Sendable` above is honest only because every access below goes through
    /// this lock.
    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    public init() {}

    @discardableResult
    public func add(
        _ account: OTPAccount,
        color: AccountColor
    ) throws(SecretStoreError) -> AccountRecord {
        lock.lock()
        defer { lock.unlock() }

        let record = AccountRecord(
            id: UUID(),
            metadata: AccountMetadata(
                issuer: account.issuer,
                name: account.name,
                generator: account.generator,
                color: color,
                sortIndex: (entries.values.map(\.metadata.sortIndex).max() ?? -1) + 1
            )
        )

        entries[record.id] = Entry(metadata: record.metadata, secret: account.secret)
        return record
    }

    public func records() throws(SecretStoreError) -> [AccountRecord] {
        lock.lock()
        defer { lock.unlock() }

        return entries
            .map { AccountRecord(id: $0.key, metadata: $0.value.metadata) }
            .sorted {
                ($0.metadata.sortIndex, $0.metadata.name) < ($1.metadata.sortIndex, $1.metadata.name)
            }
    }

    public func secret(for id: UUID) throws(SecretStoreError) -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[id] else {
            throw SecretStoreError.notFound
        }

        return entry.secret
    }

    public func update(_ record: AccountRecord) throws(SecretStoreError) {
        lock.lock()
        defer { lock.unlock() }

        guard entries[record.id] != nil else {
            throw SecretStoreError.notFound
        }

        entries[record.id]?.metadata = record.metadata
    }

    public func delete(id: UUID) throws(SecretStoreError) {
        lock.lock()
        defer { lock.unlock() }

        guard entries.removeValue(forKey: id) != nil else {
            throw SecretStoreError.notFound
        }
    }
}
