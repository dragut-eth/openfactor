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
            AccountListView(store: store)
                // Accounts saved before the shared access group was declared are still in
                // the app's bundle group. The phone reads them either way, so nothing looks
                // wrong here; the watch cannot see them at all. Idempotent and cheap once
                // there is nothing left to move, so it runs at every launch rather than
                // behind a flag that could itself be wrong.
                //
                // A failure is not surfaced. Nothing is lost by it, the accounts stay
                // exactly where they are and the phone still shows them, and an alert at
                // launch about Keychain access groups would alarm without informing.
                .task { try? store.migrateToDefaultAccessGroup() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    lock.scenePhaseChanged(to: phase)
                    updateShield(for: phase)
                }
                .onChange(of: lock.isLocked) {
                    updateShield(for: scenePhase)
                }
                .preferredColorScheme(
                    (AppearancePreference(rawValue: appearance) ?? .system).colorScheme
                )
        }
    }

    /// While locked the lock screen wins whatever the phase, because it hides the
    /// interface just as thoroughly as the cover and it is what belongs in the system's
    /// snapshot. The cover appears for everyone else the moment the app is not active,
    /// lock setting or none: the app switcher photograph must never contain a code.
    private func updateShield(for phase: ScenePhase) {
        if lock.isLocked {
            PrivacyShield.update(.locked, controller: lock)
        } else if phase != .active {
            PrivacyShield.update(.cover, controller: lock)
        } else {
            PrivacyShield.update(nil, controller: lock)
        }
    }
}
