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
/// So the vault's most consequential decisions, which of the three states a device is in, whether
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
}

extension WrappedKeyStore: WrappedRecordStore {}
