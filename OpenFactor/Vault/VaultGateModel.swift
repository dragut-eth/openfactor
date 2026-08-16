import Foundation
import OpenFactorCore
import SwiftUI

/// The decision that comes before the account list: does this device have the key to open its
/// own accounts, and if not, which of the two questions should it ask.
///
/// ## Why the passphrase is generated before the vault is
///
/// `docs/VAULT.md` requires that no vault exist whose passphrase has not been shown and
/// acknowledged. `Vault.create()` cannot give that, because it creates and then hands back a
/// string: a process killed in the gap leaves a vault whose passphrase no longer exists
/// anywhere, and nothing later can recover it. So this generates first, shows it, waits for the
/// acknowledgement, and only then calls `Vault.create(with:)`. Until that call nothing has been
/// written and abandoning the screen costs nothing.
///
/// ## Why creation is never automatic
///
/// Absent and locked look the same for as long as iCloud Keychain takes to deliver the wrapped
/// record, which this project has measured at close to half an hour. A device that created a
/// vault on its own during that window would strand every account sealed under the first one,
/// silently, and the person would have two passphrases and no way to know which was which.
/// Creation is therefore a button somebody presses, on a screen that says what waiting looks
/// like, and the state is re-read whenever the app comes forward so a record that arrives while
/// the screen is open moves it to the unlock question by itself.
@MainActor
@Observable
final class VaultGateModel {

    enum Stage: Equatable {
        /// Before the first read. Distinct from `introducing` so a launch does not flash the
        /// setup screen at a device that turns out to be perfectly fine.
        case checking
        /// No key and no record: offer to create, and explain what waiting looks like.
        case introducing
        /// A passphrase exists in memory and has been shown. Nothing is stored yet.
        case showingPassphrase(String)
        /// Ciphertext is here and the key is not.
        case locked
        case open
    }

    private(set) var stage: Stage = .checking

    /// Set while a key derivation is running. Both paths take a few hundred milliseconds of
    /// PBKDF2, which is the point of PBKDF2.
    private(set) var isWorking = false

    /// The acknowledgement. Nothing is written until this is true.
    var hasSavedPassphrase = false

    /// What the person types on the unlock screen.
    var typedPassphrase = ""

    private(set) var failure: String?

    private let vault: Vault

    init(vault: Vault) {
        self.vault = vault
    }

    // MARK: - Reading the state

    /// Re-reads which of the three states this device is in.
    ///
    /// Deliberately does nothing while a passphrase is on screen. That stage exists only in
    /// memory and the device is still genuinely `absent`, so refreshing would throw away a
    /// passphrase somebody may be halfway through writing down.
    func refresh() {
        if case .showingPassphrase = stage { return }
        if isWorking { return }

        switch vault.state() {
        case .open: stage = .open
        case .locked: stage = .locked
        case .absent: stage = .introducing
        }
    }

    // MARK: - Creating

    /// Generates a passphrase and shows it. **Writes nothing.**
    func offerPassphrase() {
        hasSavedPassphrase = false
        failure = nil

        guard let generated = BackupPassphrase.generate() else {
            failure = "A passphrase could not be generated. Try again."
            return
        }

        stage = .showingPassphrase(generated)
    }

    /// Creates the vault, now that the passphrase has been shown and acknowledged.
    func createVault() async {
        guard case let .showingPassphrase(generated) = stage, hasSavedPassphrase else { return }

        isWorking = true
        failure = nil
        defer { isWorking = false }

        let passphrase = BackupPassphrase.grouped(generated)

        guard await Self.create(vault, with: passphrase) == nil else {
            // Deliberately vague about the cause and specific about the consequence. Every
            // failure here means the same thing to the person holding the phone: nothing was
            // set up, and pressing the button again is the whole of the remedy.
            failure = "Your accounts could not be set up. Try again."
            return
        }

        typedPassphrase = ""
        stage = .open
    }

    /// Throws the shown passphrase away and generates another. For the case where somebody
    /// mistyped it into wherever they keep it and would rather start again than be unsure.
    func discardPassphrase() {
        stage = .introducing
        hasSavedPassphrase = false
    }

    // MARK: - Unlocking

    func unlock() async {
        let attempt = typedPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attempt.isEmpty, !isWorking else { return }

        isWorking = true
        failure = nil
        defer { isWorking = false }

        guard let error = await Self.unlock(vault, with: attempt) else {
            typedPassphrase = ""
            stage = .open
            return
        }

        switch error {
        case .wrongPassphrase:
            // Says only that it did not open. It cannot distinguish a wrong passphrase from
            // an altered record, and guessing between them would put a wrong explanation in
            // front of somebody at the worst possible moment.
            failure = "That did not open your accounts. Check for a mistyped character."
        case .nothingToUnlock:
            failure = "There is nothing on this iPhone to unlock."
            stage = .introducing
        case .storage:
            failure = "Your accounts could not be reached. Try again."
        }
    }

    // MARK: - Starting over

    /// Forgets the key and the wrapped record, after the accounts themselves have gone.
    ///
    /// **Only ever called from the erase flow**, which authenticates and requires a typed word.
    /// On its own this would leave ciphertext that nothing could ever open, so it runs after the
    /// accounts are already deleted and never instead of deleting them.
    func destroyVault() {
        try? vault.destroy()
        hasSavedPassphrase = false
        typedPassphrase = ""
        refresh()
    }

    // MARK: - Off the main thread

    // PBKDF2 at 600,000 iterations is hundreds of milliseconds by design. Run on the main actor
    // it would freeze the interface at the two moments the app most needs to look deliberate.

    /// `nil` on success. A `Result` was the first shape and it did not survive typed throws:
    /// inside a non-throwing closure the `catch` binds `any Error`, so the error has to be
    /// matched back to its type rather than simply forwarded.
    private static func create(
        _ vault: Vault, with passphrase: String
    ) async -> Vault.VaultError? {
        await Task.detached(priority: .userInitiated) {
            do {
                try vault.create(with: passphrase)
                return nil
            } catch let error as Vault.VaultError {
                return error
            } catch {
                return Vault.VaultError.storage(.keychain(status: -1))
            }
        }.value
    }

    private static func unlock(
        _ vault: Vault, with passphrase: String
    ) async -> Vault.VaultError? {
        await Task.detached(priority: .userInitiated) {
            do {
                try vault.unlock(with: passphrase)
                return nil
            } catch let error as Vault.VaultError {
                return error
            } catch {
                return Vault.VaultError.storage(.keychain(status: -1))
            }
        }.value
    }
}
