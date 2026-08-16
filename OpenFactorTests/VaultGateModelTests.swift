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

    @Test("Asking for a different passphrase forgets the first and still writes nothing")
    func discardingReturnsToTheStart() throws {
        let (gate, vault, _, wrapped) = makeGate()
        defer { try? wrapped.delete() }

        gate.refresh()
        gate.offerPassphrase()
        gate.hasSavedPassphrase = true
        gate.discardPassphrase()

        #expect(gate.stage == .introducing)
        // The acknowledgement must not carry over to a passphrase nobody has seen yet.
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
