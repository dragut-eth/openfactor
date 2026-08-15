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

    /// Moves a counter based account to its next code.
    ///
    /// Counter based codes do not advance with the clock. They advance when the user asks
    /// for one, which makes the counter state the app owns and must not lose.
    ///
    /// **The new counter is stored before the code is returned, deliberately.** If the app
    /// dies between the two, the user sees no code and asks again, which costs them a tap.
    /// The other order loses the count: the user reads a code, the app forgets it ever
    /// advanced, and the next request repeats a code the service has already consumed.
    /// Services reject a replayed counter, so that failure is silent until a login fails.
    ///
    /// Advancing lives here rather than at a call site so the order cannot be got wrong by
    /// whoever writes the next screen, and so it can never be done through a plain
    /// metadata update. Written to the rules recorded as finding F4 at gate A1.
    ///
    /// - Returns: the updated record and the code its new counter produces.
    public func advancingCounter(
        for record: AccountRecord
    ) throws(SecretStoreError) -> (record: AccountRecord, code: String) {
        guard case let .hotp(counter, digits, algorithm) = record.metadata.generator else {
            throw SecretStoreError.notCounterBased
        }

        // Checked, not wrapping. Wrapping would send the account back to counter zero and
        // replay every code it has ever produced.
        let (next, overflowed) = counter.addingReportingOverflow(1)
        guard !overflowed else {
            throw SecretStoreError.counterExhausted
        }

        var advanced = record
        advanced.metadata.generator = .hotp(counter: next, digits: digits, algorithm: algorithm)

        try update(advanced)

        let code = HOTP.code(
            secret: try secret(for: record.id),
            counter: next,
            digits: digits,
            algorithm: algorithm
        )

        return (advanced, code)
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


/// A store that can put its accounts in iCloud Keychain, or take them back out.
///
/// Deliberately separate from ``SecretStore`` rather than a method on it. Only a Keychain
/// backed store can sync, and giving ``InMemorySecretStore`` a method that pretends to
/// would make the interface show a switch that does nothing. Code that offers sync asks
/// for this protocol, and a store that cannot provide it simply does not offer the choice.
public protocol SynchronizableSecretStore: SecretStore {

    /// Turns sync on or off for every stored account, and returns how many changed.
    @discardableResult
    func setSynchronizable(_ shouldSync: Bool) throws(SecretStoreError) -> Int
}
