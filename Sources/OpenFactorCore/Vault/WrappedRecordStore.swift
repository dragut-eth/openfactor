import Foundation

/// Where the wrapped vault key lives, as the vault sees it.
///
/// ## Why this protocol exists
///
/// `Vault` held a `WrappedKeyStore` directly, which is the Keychain. **The Keychain is not
/// available to this package's tests**: the test binary is unsigned, so `SecItemAdd` returns
/// `errSecMissingEntitlement`, and the entire `Vault lifecycle` suite is skipped on the machine
/// the suite runs on. That was discovered while writing tests for gate A4's scope 1 findings, by
/// deliberately breaking each fix and watching the suite stay green.
///
/// So the vault's most consequential decisions, which state a device is in, whether
/// creating would destroy an existing record, whether a refused record is a wrong passphrase or
/// an unreadable one, were argued for in comments and verified by nobody. That is the same
/// condition gate A4 found in the watch's view model, and it produced defects there in three
/// consecutive rounds.
///
/// The vault takes one of these instead. `WrappedKeyStore` is the one the app uses; the tests
/// supply one that keeps a record in memory and can be told to fail, which is how the states
/// this protocol makes reachable are actually checked.
///
/// **The Keychain implementation is not thereby untested.** `KeychainSecretStoreTests` covers it
/// directly and is skipped on the same machine for the same reason, so what this changes is which
/// layer the gap sits in: the storage adapter rather than the decisions above it.
public protocol WrappedRecordStore: Sendable {

    /// The record, or `nil` when there is none. Throwing means the store could not be read at
    /// all, which is deliberately different from finding nothing. See `Vault.State.unavailable`.
    func load() throws(SecretStoreError) -> Data?

    /// Stores the record, replacing any earlier one.
    func save(_ record: Data) throws(SecretStoreError)

    func delete() throws(SecretStoreError)

    /// Every wrapped record this device can see, under either sync flag.
    ///
    /// **There should be one, and the whole of S1-12 is that there can be two.**
    /// `kSecAttrSynchronizable` is part of a Keychain item's primary key, so a record carrying the
    /// opposite flag is a different item rather than a duplicate: `addIfAbsent` narrows that window
    /// and cannot close it, because a record can arrive from iCloud minutes after the check. When
    /// it happens, `load()` returns one of them and which one is unspecified, so a correct
    /// passphrase can be tested against the wrong wrap and reported as wrong.
    ///
    /// Returning all of them is what lets `unlock` settle it without asking anybody anything.
    func candidates() throws(SecretStoreError) -> [WrappedCandidate]

    /// Removes one specific record, identified by the flag that distinguishes it from its twin.
    func discard(_ candidate: WrappedCandidate) throws(SecretStoreError)

    /// Stores the record **only if the store is empty**, and says which happened.
    ///
    /// - Returns: `true` when this call is what put the record there. `false` when something was
    ///   already present.
    ///
    /// **`false` does not promise that nothing was written**, and it used to say it did. The
    /// Keychain implementation cannot see a record carrying the opposite sync flag until after it
    /// has added its own, so it adds, counts, and removes what it wrote. If that removal fails,
    /// both records remain and the caller is still told `false`. Round three of gate A4 found the
    /// promise and the implementation disagreeing.
    ///
    /// **Why this exists, and why `save` cannot be used for creation.** `save` replaces whatever
    /// it finds, which is right for a passphrase change and catastrophic for a first write. Gate
    /// A4's round two of this scope found the hole, and two engines walked it out independently:
    /// `create(with:)` asked `state()` whether a record existed, then spent hundreds of
    /// milliseconds deriving a key at 600,000 PBKDF2 iterations, and only then called `save`. A
    /// wrapped record arriving from iCloud inside that window was replaced by a wrap of a brand
    /// new vault key, and every account already sealed under the old one became unopenable by
    /// anybody, including the person holding the correct passphrase.
    ///
    /// **The check has to be part of the write.** A check hundreds of milliseconds earlier is not
    /// a check, and the test that covered it could not see the difference because its fake record
    /// never changed between the two.
    func addIfAbsent(_ record: Data) throws(SecretStoreError) -> Bool
}

extension WrappedKeyStore: WrappedRecordStore {}

/// One wrapped record, and the flag that tells it apart from a twin.
public struct WrappedCandidate: Sendable, Equatable {

    public let record: Data

    /// Whether this copy is the one offered to iCloud. Two records differing only in this are the
    /// twin case, and it is how the loser is named once the passphrase has picked a winner.
    public let isSynchronizable: Bool

    public init(record: Data, isSynchronizable: Bool) {
        self.record = record
        self.isSynchronizable = isSynchronizable
    }
}
