import CryptoKit
import Foundation
@testable import OpenFactorCore
import Testing

@testable import OpenFactor

/// The gate's state machine, and the one property the whole screen exists to hold:
/// **nothing is stored until the passphrase has been shown and acknowledged.**
///
/// These are here rather than driven through the interface because the interface cannot be
/// driven reliably enough to trust: a simulator session verifying this by hand spent half an
/// hour on taps that silently never landed. What the screens owe is stated as assertions on the
/// model instead, where a regression fails a run rather than a person's accounts.
@MainActor
@Suite("Vault gate")
struct VaultGateModelTests {

    private func makeGate() -> (VaultGateModel, Vault, VaultKeyStore, WrappedKeyStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        let wrapped = WrappedKeyStore(service: "app.openfactor.tests.\(UUID().uuidString)")
        let vault = Vault(keys: keys, wrapped: wrapped)
        return (VaultGateModel(vault: vault), vault, keys, wrapped)
    }

    // MARK: - Which question the device asks

    @Test("Before anything is read the gate shows nothing rather than guessing")
    func startsChecking() {
        let (gate, _, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        #expect(gate.stage == .checking)
    }

    @Test("A device with nothing is offered a vault")
    func absentIntroduces() {
        let (gate, _, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        #expect(gate.stage == .introducing)
    }

    /// The distinction that cannot be got wrong. A device holding ciphertext must be asked for
    /// the passphrase it already has, never offered a new one.
    @Test("A device holding ciphertext and no key is asked to unlock, never to create")
    func lockedAsksForThePassphrase() throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try keys.discard()

        gate.refresh()
        #expect(gate.stage == .locked)
        #expect(gate.stage != .introducing)
    }

    @Test("A device with a key goes straight through")
    func openPassesThrough() throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()

        gate.refresh()
        #expect(gate.stage == .open)
    }

    // MARK: - Nothing exists before it is acknowledged

    /// The invariant `docs/VAULT.md` states, asserted rather than described: showing a
    /// passphrase must write nothing at all. A person who backs out here, or whose phone dies
    /// here, must find the device exactly as they left it.
    @Test("Showing a passphrase creates no vault")
    func offeringWritesNothing() throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()

        guard case .showingPassphrase = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        #expect(try keys.load() == nil)
        #expect(try wrapped.load() == nil)
        #expect(vault.state() == .absent)
    }

    // MARK: - What may take a passphrase off the screen

    /// A wrapped store that can be told to fail, so the gate can be driven into the one state
    /// whose defining property is not knowing.
    private final class FailingStore: WrappedRecordStore, @unchecked Sendable {
        var record: Data?
        var readFailure: SecretStoreError?

        func load() throws(SecretStoreError) -> Data? {
            if let readFailure { throw readFailure }
            return record
        }
        func save(_ record: Data) throws(SecretStoreError) { self.record = record }
        func delete() throws(SecretStoreError) { record = nil }
        func addIfAbsent(_ record: Data) throws(SecretStoreError) -> Bool {
            guard self.record == nil else { return false }
            self.record = record
            return true
        }
    }

    private func makeGate(on store: FailingStore) -> (VaultGateModel, VaultKeyStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        return (VaultGateModel(vault: Vault(keys: keys, wrapped: store)), keys)
    }

    /// **All three engines of round two found this**, and it had no test, which the same round
    /// pointed out. A transient read failure returns `.unavailable`, and the first version of the
    /// guard covered only `.absent`, so coming back to the app at the wrong moment replaced the
    /// screen and discarded the only copy of the passphrase.
    @Test("A store that cannot be read does not take the passphrase off the screen")
    func unreadableStoreLeavesThePassphraseUp() {
        let store = FailingStore()
        let (gate, _) = makeGate(on: store)

        gate.refresh()
        gate.offerPassphrase()
        guard case let .showingPassphrase(shown) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        store.readFailure = .keychain(status: errSecInteractionNotAllowed)
        gate.refresh()

        guard case let .showingPassphrase(afterwards) = gate.stage else {
            Issue.record("the passphrase must stay on screen when nothing is known")
            return
        }
        #expect(afterwards == shown, "and it must be the same one")
    }

    /// The direction that must still work: a record has arrived, so the displayed passphrase is
    /// not the one that opens this vault and the screen has to change.
    @Test("A record arriving does take the passphrase off the screen")
    func arrivingRecordMovesToUnlock() {
        let store = FailingStore()
        let (gate, _) = makeGate(on: store)

        gate.refresh()
        gate.offerPassphrase()

        store.record = Data("a wrapped key from another device".utf8)
        gate.refresh()

        #expect(gate.stage == .locked, "the passphrase on screen opens nothing, and this says so")
    }

    /// And the ordinary case, which is somebody switching apps to write the passphrase down.
    @Test("Coming back to a still-empty device leaves the passphrase alone")
    func stillAbsentLeavesThePassphrase() {
        let store = FailingStore()
        let (gate, _) = makeGate(on: store)

        gate.refresh()
        gate.offerPassphrase()
        guard case let .showingPassphrase(shown) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        gate.refresh()
        gate.refresh()

        guard case let .showingPassphrase(afterwards) = gate.stage else {
            Issue.record("the passphrase must survive an ordinary return to the app")
            return
        }
        #expect(afterwards == shown)
    }

    @Test("Continuing without the acknowledgement creates nothing")
    func acknowledgementIsRequired() async throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()
        gate.hasSavedPassphrase = false

        await gate.createVault()

        #expect(vault.state() == .absent)
        guard case .showingPassphrase = gate.stage else {
            Issue.record("the passphrase must stay on screen")
            return
        }
    }

    @Test("Acknowledging and continuing creates the vault the passphrase opens")
    func acknowledgingCreates() async throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()

        guard case let .showingPassphrase(shown) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        gate.hasSavedPassphrase = true
        await gate.createVault()

        #expect(gate.stage == .open)
        #expect(vault.state() == .open)

        // The string that was on the screen is the string that opens it. Anything else would be
        // a passphrase somebody wrote down for a vault it does not unlock, which is the failure
        // this whole two-step sequence exists to make impossible.
        let created = try #require(try keys.load())
        try keys.discard()
        try vault.unlock(with: BackupPassphrase.grouped(shown))
        let recovered = try #require(try keys.load())
        #expect(
            recovered.withUnsafeBytes { Data($0) } == created.withUnsafeBytes { Data($0) })
    }

    /// "Show me a different one" used to return to the intro screen, which is not what the
    /// label says, and read as a bug because it was one. This is the behaviour it claims.
    @Test("Asking for a different passphrase shows a different one, in place")
    func askingForAnotherShowsAnother() throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()
        guard case let .showingPassphrase(first) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        gate.hasSavedPassphrase = true
        gate.offerPassphrase()

        guard case let .showingPassphrase(second) = gate.stage else {
            Issue.record("it must stay on the passphrase screen")
            return
        }
        #expect(first != second)

        // The part that matters. A tick carried over to a string nobody has read yet would
        // defeat the only guard this screen has.
        #expect(!gate.hasSavedPassphrase)
        #expect(vault.state() == .absent)
    }

    /// A refresh arriving while a passphrase is on screen must not wipe it. The device really is
    /// `absent` at that moment, so an honest re-read would throw away a string somebody may be
    /// halfway through copying down.
    @Test("A refresh does not clear a passphrase that is being written down")
    func refreshLeavesTheScreenAlone() {
        let (gate, _, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()

        guard case let .showingPassphrase(first) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }

        gate.refresh()

        guard case let .showingPassphrase(second) = gate.stage else {
            Issue.record("the passphrase must survive a refresh")
            return
        }
        #expect(first == second)
    }

    // MARK: - Unlocking

    @Test("The passphrase from creation opens a device that only has ciphertext")
    func unlockingWorks() async throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()
        guard case let .showingPassphrase(shown) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }
        gate.hasSavedPassphrase = true
        await gate.createVault()

        try keys.discard()
        gate.refresh()
        #expect(gate.stage == .locked)

        gate.typedPassphrase = BackupPassphrase.grouped(shown)
        await gate.unlock()

        #expect(gate.stage == .open)
        #expect(vault.state() == .open)
        // Not left in a field, in a view, or anywhere else once it has been used.
        #expect(gate.typedPassphrase.isEmpty)
    }

    /// Grouping and case are presentation. Somebody reading six groups off a card should not be
    /// refused for typing them the way they are written, or for not typing the dashes at all.
    @Test(
        "The passphrase is accepted however it was written down",
        arguments: [0, 1, 2, 3])
    func unlockingToleratesFormatting(variant: Int) async throws {
        let (gate, _, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()
        guard case let .showingPassphrase(shown) = gate.stage else {
            Issue.record("expected a passphrase to be on screen")
            return
        }
        gate.hasSavedPassphrase = true
        await gate.createVault()
        try keys.discard()
        gate.refresh()

        let grouped = BackupPassphrase.grouped(shown)
        gate.typedPassphrase =
            switch variant {
            case 0: grouped
            case 1: shown
            case 2: grouped.lowercased()
            default: "  \(grouped)\n"
            }

        await gate.unlock()
        #expect(gate.stage == .open)
    }

    @Test("A wrong passphrase says so and leaves the device locked")
    func wrongPassphraseIsRefused() async throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try keys.discard()
        gate.refresh()

        gate.typedPassphrase = "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF"
        await gate.unlock()

        #expect(gate.stage == .locked)
        #expect(gate.failure != nil)
        // Kept, so the mistyped character can be found and corrected rather than retyped whole.
        #expect(!gate.typedPassphrase.isEmpty)
    }

    @Test("An empty field does nothing rather than reporting a wrong passphrase")
    func emptyAttemptIsNotAFailure() async throws {
        let (gate, vault, keys, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        try keys.discard()
        gate.refresh()

        gate.typedPassphrase = "   "
        await gate.unlock()

        #expect(gate.failure == nil)
        #expect(gate.stage == .locked)
    }

    // MARK: - A key that opens nothing

    /// The two-iPhone case, reproduced rather than described: this device holds a key, the vault
    /// was replaced elsewhere, and every record that synced is sealed under the new one.
    ///
    /// Before this, the gate saw a key, said open, and drew a list of accounts none of which
    /// could be read, blaming a legacy item or a newer version of the app. Neither was true, and
    /// the passphrase that would have fixed it in seconds was never offered.
    @Test("A device holding the wrong key is sent to the unlock screen")
    func wrongKeyAsksForThePassphrase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        let wrapped = WrappedKeyStore(service: "app.openfactor.tests.\(UUID().uuidString)")
        let vault = Vault(keys: keys, wrapped: wrapped)
        defer { try? wrapped.delete() }

        _ = try vault.create()
        let store = KeychainSecretStore(
            service: "app.openfactor.tests.\(UUID().uuidString)",
            synchronizable: false,
            vaultKeys: keys)
        _ = try store.add(
            OTPAccount(
                issuer: "Example", name: "someone", secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)),
            color: .blue)

        // Everything is fine until the vault is replaced somewhere else.
        let openGate = VaultGateModel(vault: vault, store: store)
        openGate.refresh()
        #expect(openGate.stage == .open)

        try keys.install(SymmetricKey(size: .bits256))

        let staleGate = VaultGateModel(vault: vault, store: store)
        staleGate.refresh()
        #expect(staleGate.stage == .locked)
    }

    /// The case that would send a device to the unlock screen every time it got ahead of iCloud.
    @Test("An empty store with a key is open, not locked")
    func emptyStoreStaysOpen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString)")
        let keys = VaultKeyStore(directory: { directory })
        let wrapped = WrappedKeyStore(service: "app.openfactor.tests.\(UUID().uuidString)")
        let vault = Vault(keys: keys, wrapped: wrapped)
        defer { try? wrapped.delete() }

        _ = try vault.create()
        let store = KeychainSecretStore(
            service: "app.openfactor.tests.\(UUID().uuidString)",
            synchronizable: false,
            vaultKeys: keys)

        let gate = VaultGateModel(vault: vault, store: store)
        gate.refresh()
        #expect(gate.stage == .open)
    }

    /// A gate with no store to consult must behave exactly as it did before this existed.
    @Test("Without a store the three states are unchanged")
    func noStoreIsUnchanged() throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        gate.refresh()
        #expect(gate.stage == .open)
    }

    // MARK: - Starting over

    @Test("Destroying returns the device to the beginning")
    func destroyingResets() async throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        _ = try vault.create()
        gate.refresh()
        #expect(gate.stage == .open)

        gate.destroyVault()

        #expect(gate.stage == .introducing)
        #expect(vault.state() == .absent)
    }
}

#if DEBUG
    /// The Debug-only reset, tested because it is destructive and because its ordering matters.
    ///
    /// A path that removes every account and the vault is not something to add on the strength of
    /// "it is only Debug". If it is worth having, it is worth checking, and the reason it sits on
    /// the model rather than in the view is that a private method on a `View` cannot be checked at
    /// all.
    @MainActor
    @Suite("Forget everything, Debug only")
    struct DebugForgetEverythingTests {

        /// A store, a vault open on the same key, and somewhere to put them.
        private func makeEverything() throws -> (VaultGateModel, Vault, KeychainSecretStore, WrappedKeyStore) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("forget-\(UUID().uuidString)")
            let keys = VaultKeyStore(directory: { directory })
            let wrapped = WrappedKeyStore(service: "app.openfactor.tests.\(UUID().uuidString)")
            let vault = Vault(keys: keys, wrapped: wrapped)
            _ = try vault.create()

            let store = KeychainSecretStore(
                service: "app.openfactor.tests.\(UUID().uuidString)",
                synchronizable: false,
                vaultKeys: keys)

            return (VaultGateModel(vault: vault), vault, store, wrapped)
        }

        private func anAccount(_ name: String) -> OTPAccount {
            OTPAccount(
                issuer: "Example",
                name: name,
                secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)
            )
        }

        @Test("Everything is gone and the device is back at the beginning")
        func forgetsEverything() throws {
            let (gate, vault, store, wrapped) = try makeEverything()
            defer { try? wrapped.delete() }

            _ = try store.add(anAccount("one"), color: .blue)
            _ = try store.add(anAccount("two"), color: .green)
            #expect(try store.records().readable.count == 2)

            UserDefaults.standard.set(true, forKey: PreferenceKey.syncEnabled)
            UserDefaults.standard.set(true, forKey: PreferenceKey.appLockEnabled)

            gate.forgetEverything(in: store)

            let left = try store.records()
            #expect(left.readable.isEmpty)
            // The unreadable ones too. An account this build cannot decode is still an account,
            // and leaving it would be a reset that reports success and leaves secrets behind.
            #expect(left.unreadable.isEmpty)

            #expect(vault.state() == .absent)
            #expect(gate.stage == .introducing)

            #expect(!UserDefaults.standard.bool(forKey: PreferenceKey.syncEnabled))
            #expect(!UserDefaults.standard.bool(forKey: PreferenceKey.appLockEnabled))
        }

        /// The ordering claim, stated as a test rather than only as a comment. Destroying the
        /// vault first would leave records nothing could ever open, and `records()` would still
        /// list them, so this asserts the end state the right order produces.
        @Test("No account survives the vault it was sealed under")
        func leavesNoOrphanedCiphertext() throws {
            let (gate, vault, store, wrapped) = try makeEverything()
            defer { try? wrapped.delete() }

            _ = try store.add(anAccount("orphan"), color: .red)

            gate.forgetEverything(in: store)

            #expect(vault.state() == .absent)
            let left = try store.records()
            #expect(left.readable.isEmpty && left.unreadable.isEmpty)
        }

        @Test("Running it on a device with nothing on it is not an error")
        func isSafeOnAFreshDevice() throws {
            let (gate, vault, store, wrapped) = try makeEverything()
            defer { try? wrapped.delete() }

            gate.forgetEverything(in: store)
            #expect(throws: Never.self) { gate.forgetEverything(in: store) }

            #expect(vault.state() == .absent)
            #expect(gate.stage == .introducing)
        }
    }
#endif
