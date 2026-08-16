import Foundation

@testable import OpenFactorCore

/// A store whose vault is already open, for tests that are about something else.
///
/// **The store deliberately will not create a vault by itself.** `docs/VAULT.md` requires that no
/// vault exists without its passphrase having been shown and acknowledged, so a device with
/// ciphertext and no key reports `.vaultLocked` rather than quietly minting one. That is correct
/// and it means every test touching accounts has to say which vault it is using.
///
/// Each call gets its **own temporary directory**, so tests cannot share a key or leak one into
/// the real application support directory of whatever process is running them.
///
/// Tests that are actually about locking should build a `VaultKeyStore` themselves and leave it
/// empty, rather than reaching for this.
enum UnlockedVault {

    /// A store with a fresh service name and a fresh vault key.
    static func store(
        service: String = "app.openfactor.tests.\(UUID().uuidString)",
        synchronizable: Bool = false
    ) throws -> KeychainSecretStore {
        // One directory, captured. Computing it inside the closure would hand back a fresh
        // path on every access, so `create` would write somewhere `load` never looks. The
        // production provider re-reads FileManager each time and gets a stable answer; a
        // provider that invents a new answer each time is a different thing entirely.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-test-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        _ = try keys.create()

        return KeychainSecretStore(
            service: service,
            synchronizable: synchronizable,
            vaultKeys: keys)
    }

    /// A store sharing an existing store's vault, for the cases that need two views of one vault.
    static func store(
        service: String,
        sharingVaultWith other: KeychainSecretStore,
        synchronizable: Bool = false
    ) -> KeychainSecretStore {
        KeychainSecretStore(
            service: service,
            synchronizable: synchronizable,
            vaultKeys: other.vaultKeys)
    }

}
