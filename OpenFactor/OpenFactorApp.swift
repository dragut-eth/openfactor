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

    var body: some Scene {
        WindowGroup {
            AccountListView(store: store)
                .preferredColorScheme(
                    (AppearancePreference(rawValue: appearance) ?? .system).colorScheme
                )
        }
    }
}
