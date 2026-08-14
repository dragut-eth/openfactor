import Foundation

/// Where accounts live.
///
/// The shape of this protocol is the security design, so it is worth reading as such
/// rather than as plumbing.
///
/// **Reading the list and reading a secret are separate operations.** ``records()``
/// returns everything needed to draw the interface and no secret material at all.
/// ``secret(for:)`` returns one secret, for the moment a single code is generated. There
/// is deliberately no call that returns every account with its secret, because the
/// interface never needs one and its existence would invite exactly the batch read this
/// design avoids.
///
/// Every method is synchronous. Keychain calls are fast local operations against an
/// already unlocked device, and making them asynchronous would add concurrency without
/// adding safety.
public protocol SecretStore: Sendable {

    /// Saves a new account and returns the stored record.
    ///
    /// The identifier and the sort position are assigned here rather than by the caller.
    /// The store is the only thing that can see the other accounts, so it is the only
    /// thing that can place a new one at the end without a race.
    @discardableResult
    func add(_ account: OTPAccount, color: AccountColor) throws(SecretStoreError) -> AccountRecord

    /// Everything needed to draw the list, sorted, and with no secret material in it.
    ///
    /// Records this version cannot decode are reported alongside the ones it can, rather
    /// than failing the read. See ``StoredRecords``.
    func records() throws(SecretStoreError) -> StoredRecords

    /// The secret for one account, for the instant a code is generated.
    func secret(for id: UUID) throws(SecretStoreError) -> Data

    /// Replaces the metadata for an existing account. Never touches its secret.
    func update(_ record: AccountRecord) throws(SecretStoreError)

    /// Deletes an account and its secret. Irreversible.
    func delete(id: UUID) throws(SecretStoreError)
}

extension SecretStore {

    /// Rebuilds a full account, secret included, for the moment a code is generated.
    ///
    /// This is the only place metadata and secret are put back together, and the result
    /// is a transient ``OTPAccount`` that is expected to be discarded immediately.
    public func account(for id: UUID) throws(SecretStoreError) -> OTPAccount {
        guard let record = try records().readable.first(where: { $0.id == id }) else {
            throw SecretStoreError.notFound
        }

        return OTPAccount(
            issuer: record.metadata.issuer,
            name: record.metadata.name,
            secret: try secret(for: id),
            generator: record.metadata.generator
        )
    }

    /// The code for one account at a given moment.
    ///
    /// The convenience worth having: the secret is read, used, and goes out of scope in
    /// one expression, so no caller has a reason to hold one.
    public func code(for id: UUID, at date: Date) throws(SecretStoreError) -> String {
        guard let record = try records().readable.first(where: { $0.id == id }) else {
            throw SecretStoreError.notFound
        }

        return try code(for: record, at: date)
    }

    /// The code for a record the caller already holds.
    ///
    /// The list has its records already, and going back through ``records()`` for each one
    /// would query the Keychain once per account per refresh. This reads exactly one item:
    /// the secret, for the instant it is used.
    public func code(for record: AccountRecord, at date: Date) throws(SecretStoreError) -> String {
        let secret = try secret(for: record.id)

        switch record.metadata.generator {
        case let .totp(configuration):
            return TOTP.code(secret: secret, at: date, configuration: configuration)
        case let .hotp(counter, digits, algorithm):
            return HOTP.code(secret: secret, counter: counter, digits: digits, algorithm: algorithm)
        }
    }
}
