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
        /// The store could not be read, so nothing is offered until it can be.
        ///
        /// **The point of this screen is what it does not offer.** The state it replaces was
        /// `introducing`, whose button creates a vault, and creating one over a record that is
        /// merely unreadable at this moment destroys every stored account. Waiting is always
        /// recoverable; creating is not.
        case unavailable
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

    /// Read to tell a key that works from one that merely exists. Optional so tests that are
    /// about the three states do not have to build a store to talk about them.
    private let store: (any SecretStore)?

    /// Set once a key has been installed and the records still will not open, which means the
    /// cause is a format this build does not understand rather than the wrong key. Without it
    /// the gate would send somebody to the unlock screen, accept a correct passphrase, and send
    /// them straight back.
    private var hasInstalledAFreshKey = false

    init(vault: Vault, store: (any SecretStore)? = nil) {
        self.vault = vault
        self.store = store
    }

    // MARK: - Reading the state

    /// Re-reads which of the three states this device is in.
    ///
    /// Deliberately does nothing while a passphrase is on screen. That stage exists only in
    /// memory and the device is still genuinely `absent`, so refreshing would throw away a
    /// passphrase somebody may be halfway through writing down.
    func refresh() {
        if isWorking { return }

        let state = vault.state()

        // **A passphrase on screen no longer blinds this.** The early return used to cover
        // every state, so a wrapped record arriving from iCloud while a generated passphrase was
        // displayed changed nothing, and the tap that followed tried to create a vault over it.
        // Nothing is lost by moving away: at this stage the passphrase has been generated and
        // not used, and no vault exists to abandon. A review found it, and the guard that would
        // have made it harmless, `create(with:)` refusing an existing record, was missing too.
        //
        // Everything else still leaves the screen alone, which is what the early return was for:
        // a scene becoming active must not clear a passphrase somebody is in the middle of
        // writing down.
        if case .showingPassphrase = stage, state == .absent { return }

        switch state {
        case .open: stage = keyOpensNothing ? .locked : .open
        case .locked: stage = .locked
        case .absent: stage = .introducing
        case .unavailable: stage = .unavailable
        }
    }

    /// **Having a key is not the same as having the right one.** Two iPhones on one Apple
    /// Account: the second replaces the vault, and the first keeps its old key while every
    /// record that syncs is sealed under the new one. Before this, that phone drew the list and
    /// showed every account as unreadable, blaming a legacy item or a newer version of the app,
    /// neither of which was true, and never offered the passphrase that would have fixed it.
    ///
    /// The remedy is the unlock screen unchanged, because its sentence is true either way: a
    /// phone holding the wrong key does not have the key that unlocks these accounts. Entering
    /// the passphrase reads the current wrapped record and installs over whatever is there.
    ///
    /// The rule is `StoredRecords.suggestsAWrongKey`, which is in the core with tests.
    private var keyOpensNothing: Bool {
        guard !hasInstalledAFreshKey, let store, let records = try? store.records() else {
            return false
        }
        return records.suggestsAWrongKey
    }

    // MARK: - Creating

    /// Generates a passphrase and shows it. **Writes nothing.**
    ///
    /// Also what "show me a different one" calls, which is the whole of that button: it used to
    /// return to the intro screen, so the label promised one thing and the code did another.
    /// Note that it clears the acknowledgement, which is the part that matters. Carrying a tick
    /// over to a string nobody has read yet would defeat the only guard on this screen.
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

        if let error = await Self.create(vault, with: passphrase) {
            // Deliberately vague about the cause and specific about the consequence. Almost
            // every failure here means the same thing to the person holding the phone: nothing
            // was set up, and pressing the button again is the whole of the remedy.
            //
            // **One of them means the opposite.** A vault that already exists, or one that
            // arrived from another device while this screen was up, is not something to try
            // again: the passphrase on this screen is not the one that opens it, and the remedy
            // is the unlock screen with the passphrase that device was given.
            if error == .alreadyExists {
                failure =
                    "Your vault already exists on this Apple Account. Enter the passphrase you "
                    + "were given when you set it up."
                stage = .locked
            } else {
                failure = "Your accounts could not be set up. Try again."
            }
            return
        }

        typedPassphrase = ""
        stage = .open
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

            // The passphrase was right and a key is installed. Whether it opens anything is a
            // different question, and the only honest way to answer it is to read with it. If it
            // does not, the cause is the format rather than the key, and the list saying so is
            // better than this screen asking again for a passphrase that already worked.
            if keyOpensNothing { hasInstalledAFreshKey = true }
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
        case .recordNotUnderstood:
            // **Not "check for a mistyped character".** This record was refused before the
            // passphrase was used for anything, so no passphrase would open it, and sending
            // somebody back to retype one they have written down correctly is the wrong
            // instruction at the worst possible moment. A review found the two collapsed.
            failure =
                "This iPhone cannot read your vault. It may have been set up by a newer "
                + "version of OpenFactor. Updating the app is the thing to try."
        case .alreadyExists:
            // Reachable only if a record arrived between the check and the write.
            failure = "Your vault is already set up on this iPhone."
            stage = .locked
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

    #if DEBUG
        /// Drops this device's key and keeps everything else, so the next screen is the unlock
        /// one. Debug builds only. Nothing is lost: the passphrase still opens it.
        func lockForDebug() {
            try? vault.discardKeyForDebug()
            typedPassphrase = ""
            refresh()
        }

        /// Returns this device to the state of an install that has never been run.
        ///
        /// **A development tool, compiled out of any build that is not Debug.** A shipped
        /// authenticator must not carry a button that destroys everything without so much as a
        /// Face ID prompt. The real erase is in Settings, behind authentication and a typed
        /// word, and this does not replace it.
        ///
        /// It exists because the setup screen can otherwise be read once per device and never
        /// again, which makes working on its wording a loop of deleting the app, reinstalling,
        /// landing on the unlock screen, and starting over.
        ///
        /// It lives on the model rather than in the view for a reason worth keeping: a private
        /// method on a `View` cannot be tested, and this one has an ordering requirement. If it
        /// were untestable it would also be unverifiable, and a destructive path nobody can
        /// check is not something to add even to a Debug build.
        ///
        /// **Accounts first, then the vault.** The other order leaves ciphertext that nothing
        /// can ever open, which is the same rule the real erase follows.
        func forgetEverything(in store: any SecretStore) {
            if let records = try? store.records() {
                for id in records.readable.map(\.id) + records.unreadable {
                    try? store.delete(id: id)
                }
            }

            destroyVault()

            // The preferences too, or the next run is a first launch with somebody else's sync
            // setting and app lock already on, which is not the thing being looked at.
            PreferenceKey.forgetEverythingForDebug()
        }
    #endif

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
