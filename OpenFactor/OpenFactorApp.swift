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
    private let store = SyncAwareKeychainStore()

    /// The lock and the snapshot cover. See `PrivacyShield` for why they live in their
    /// own window rather than in this view tree.
    @State private var lock = AppLockController()
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
                    AccountListView(store: store)
                        // Accounts saved before the shared access group was declared are
                        // still in the app's bundle group. The phone reads them either
                        // way, so nothing looks wrong here; the watch cannot see them at
                        // all. Idempotent and cheap once there is nothing left to move,
                        // so it runs at every launch rather than behind a flag that could
                        // itself be wrong.
                        //
                        // A failure is not surfaced. Nothing is lost by it, the accounts
                        // stay exactly where they are and the phone still shows them, and
                        // an alert at launch about Keychain access groups would alarm
                        // without informing.
                        .task { try? store.migrateToDefaultAccessGroup() }
                }
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

    /// The cover shows when the app is not active and not locked. Not when locked,
    /// because the lock screen is the root view then: it hides the interface just as
    /// thoroughly, and it is what belongs in the system's snapshot. When the lock is off
    /// the cover still appears for everyone, since the app switcher photograph must never
    /// contain a code.
    private func updateShield(for phase: ScenePhase) {
        PrivacyShield.setCovered(!lock.isLocked && phase != .active)
    }
}
