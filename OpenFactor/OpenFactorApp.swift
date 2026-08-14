import OpenFactorCore
import SwiftUI

@main
struct OpenFactorApp: App {

    /// The one store the app uses. Constructed here and passed down, so there is exactly
    /// one place in the app that decides where secrets live.
    ///
    /// It is deliberately not an `InMemorySecretStore`. That type exists in the library
    /// for previews and tests, and if it ever appears in this file, that is the bug.
    private let store = KeychainSecretStore()

    var body: some Scene {
        WindowGroup {
            AccountListView(store: store)
        }
    }
}
