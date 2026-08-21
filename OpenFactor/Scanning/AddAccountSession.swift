import Foundation
import OpenFactorCore

/// The add flow's state, owned by the app so App Lock cannot destroy it.
///
/// **The third instance of the pattern, and the reason it is a named thing now.** State owned
/// below the account list does not survive a locked cold launch, which is the one this app opens
/// into; `docs/APP_LOCK.md` describes the mechanism. Beneath it here was
/// somebody halfway through typing a secret key by hand. Leaving to copy that key out of an
/// email or a password manager is not an edge case of manual entry, it is how manual entry is
/// actually performed, and coming back to an empty form was reported within a day of the vault
/// passphrase being lost the same way. The vault gate and the pending arrival already live
/// above the lock for the same reason.
///
/// ## How a lock is told apart from a dismissal
///
/// Nothing here inspects the lock, and nothing needs to. **No teardown the lock causes flips
/// `isPresented`**, because the binding lives on this object and the object lives on the app. Cancel, a swipe down, and a completed add all flip it. So the app resets
/// this session whenever `isPresented` turns false, and a locked teardown, which never turns it
/// false, re-presents the same screens with the same typed text when the tree returns.
///
/// A deliberate consequence: swiping the sheet away mid-entry discards the draft, exactly as it
/// did when the state lived in the view. Dismissal means discard; only the lock means resume.
@MainActor
@Observable
final class AddAccountSession {

    /// Whether the add sheet is up. The one bit the lock can never touch.
    var isPresented = false

    /// Whether the manual entry screen is pushed over the scanner.
    var isEnteringManually = false

    /// The scanner's state: looking, confirming one account, or holding a transfer.
    private(set) var scan: AddAccountViewModel

    /// The manual form, which is where the typing that must survive actually lives.
    private(set) var manual: ManualSetupViewModel

    let store: any SecretStore

    init(store: any SecretStore) {
        self.store = store
        scan = AddAccountViewModel(store: store)
        manual = ManualSetupViewModel(store: store)
    }

    /// Fresh models for the next opening. Called by the app when the sheet is dismissed, and
    /// never by the lock, which is the entire point of the arrangement.
    func reset() {
        scan = AddAccountViewModel(store: store)
        manual = ManualSetupViewModel(store: store)
        isEnteringManually = false
    }
}
