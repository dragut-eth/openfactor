import OpenFactorCore
import SwiftUI

@main
struct OpenFactorApp: App {

    /// The colour scheme override, applied at the root so every sheet inherits it.
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearancePreference.system.rawValue

    /// The one store the app uses. Constructed here and passed down, so there is exactly
    /// one place in the app that decides where secrets live.
    ///
    /// It is deliberately not an `InMemorySecretStore`. That type exists in the library
    /// for previews and tests, and if it ever appears in this file, that is the bug.
    ///
    /// No access group is named here on purpose. The entitlement declares exactly one, and
    /// the Keychain uses the first group in that list as the default for anything written
    /// without one. Naming it in code would mean hardcoding the team identifier, which does
    /// not belong in a public repository, and would give the group two homes that could
    /// disagree. The entitlement is the single place it is written down.
    private let store: SyncAwareKeychainStore

    /// This device's vault, sharing the very same key store the accounts are read through.
    ///
    /// One `VaultKeyStore` instance rather than two. Both defaults point at the same file, so
    /// two would behave identically today, and the day somebody changes where the key lives is
    /// the day two would silently disagree: the gate would report a vault open that the store
    /// could not read.
    private let vault: Vault

    init() {
        let keys = VaultKeyStore()
        store = SyncAwareKeychainStore(vaultKeys: keys)
        vault = Vault(keys: keys)
    }

    /// The lock and the snapshot cover. See `PrivacyShield` for why they live in their
    /// own window rather than in this view tree.
    @State private var lock = AppLockController()

    /// Answers a watch asking for the vault key. The only path by which that key leaves this
    /// device, and the only reason this app talks to the watch at all.
    @State private var watchKeys = WatchKeyProvider()

    /// Set when the access group migration could not finish. See the alert below.
    ///
    /// Held as a flag rather than the error: reading through the store's existential
    /// widens the typed throw, and the alert says the same thing whatever went wrong.
    @State private var migrationFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                // While locked the interface does not exist, rather than existing behind
                // a cover. The first version drew the list as the root and locked over
                // it, which leaked a frame of the list at every locked launch: whatever
                // renders first is what the person sees first, so the lock screen has to
                // BE the root, not arrive on top of it. Swapping the branch also tears
                // down any open sheet, so nothing locked lingers mid air.
                if lock.isLocked {
                    LockScreenView(controller: lock)
                } else {
                    // The vault gate, not the list. A device that has accounts and no key must
                    // ask for its passphrase before anything is drawn, and a device that has
                    // never had a vault must be offered one: the list cannot render either
                    // state honestly, because to it both look like a shelf of unreadable rows.
                    VaultGateView(vault: vault, store: store) {
                        AccountListView(store: store)
                        // Accounts saved before the shared access group was declared are
                        // still in the app's bundle group. The phone reads them either
                        // way, so nothing looks wrong here; the watch cannot see them at
                        // all. Idempotent and cheap once there is nothing left to move,
                        // so it runs at every launch rather than behind a flag that could
                        // itself be wrong.
                        //
                        // A failure used to be swallowed here, on the reasoning that
                        // nothing is lost by it. That reasoning was wrong in one direction
                        // that matters: an account left in the old group is invisible on
                        // this phone, which reads every group it can reach, and shows up
                        // only as a watch with fewer accounts than it should have and no
                        // error anywhere. That is the exact bug this migration exists to
                        // fix, so failing to migrate must not be silent. Gate A2, F20.
                        .task {
                            do {
                                try store.migrateToDefaultAccessGroup()
                                migrationFailed = false
                            } catch {
                                migrationFailed = true
                            }
                        }
                        .alert(
                            "Some accounts were not moved",
                            isPresented: $migrationFailed
                        ) {
                            Button("OK") { migrationFailed = false }
                        } message: {
                            Text(
                                """
                                They are safe and still on this phone, but they will not \
                                reach your Apple Watch. Reopening OpenFactor tries again.
                                """
                            )
                        }
                    }
                }
            }
            // Anything a previous run left behind, removed before the interface exists.
            // The export screen deletes its own file when it goes away, which covers every
            // way a screen goes away and not the one where the process does not: force quit
            // from the app switcher, or an out of memory kill, while the file is on screen.
            // For the plaintext vault that would be every secret in the clear, sitting in
            // the container with nothing ever revisiting it. Found by the security review.
            .task { ExportViewModel.discardOrphanedFiles() }
            .task { watchKeys.activate() }
            // Over whatever is on screen, because the watch may ask at any moment and the
            // answer is the same wherever the person happens to be in the app. It cannot
            // appear while locked: the lock screen is the root then, and this modifier is
            // attached above it deliberately so the question waits rather than being missed.
            .alert("Set up your Apple Watch?", isPresented: watchAsking) {
                Button("Not now", role: .cancel) { watchKeys.decline() }
                Button("Set up Apple Watch") { watchKeys.approve() }
            } message: {
                // One line. The system alert is translucent on iOS 26 and this one lands on the
                // account list, which is a wall of saturated color, so every word that is not
                // load bearing is working against being read at all.
                Text("Your Apple Watch is asking for the key to your accounts.")
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                lock.scenePhaseChanged(to: phase)
                updateShield(for: phase)
            }
            .onChange(of: lock.isLocked) {
                updateShield(for: scenePhase)
            }
            // The root swap and the shield hide land in the same transaction, so there is
            // no frame between them for the interface to show through.
            .preferredColorScheme(
                (AppearancePreference(rawValue: appearance) ?? .system).colorScheme
            )
        }
    }

    /// The alert's binding. **The setter deliberately does nothing.**
    ///
    /// It used to decline on dismissal, on the reasoning that a question about releasing a key
    /// must never resolve as yes by default. That was right in intent and wrong in mechanism:
    /// SwiftUI sets this binding to false as part of dismissing the alert, *before* the button's
    /// action runs, so pressing "Set up Apple Watch" declined first and then found nothing left
    /// to approve. It failed every single time, which is what a deterministic ordering bug looks
    /// like from the outside.
    ///
    /// The intent is preserved without the mechanism: both buttons answer explicitly, and an
    /// alert that somehow goes away without either leaves the question unanswered, so it comes
    /// back rather than resolving itself.
    private var watchAsking: Binding<Bool> {
        Binding(
            get: { watchKeys.isAsking && !lock.isLocked },
            set: { _ in })
    }

    /// The cover shows when the app is not active and not locked. Not when locked,
    /// because the lock screen is the root view then: it hides the interface just as
    /// thoroughly, and it is what belongs in the system's snapshot. When the lock is off
    /// the cover still appears for everyone, since the app switcher photograph must never
    /// contain a code.
    private func updateShield(for phase: ScenePhase) {
        PrivacyShield.setCovered(!lock.isLocked && phase != .active)
    }
}
