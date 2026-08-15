import OpenFactorCore
import SwiftUI

/// The watch app.
///
/// **Read only, and that is a security property rather than a scope decision.** The watch
/// shows the list and a code. It cannot add, edit, delete, or copy. The smallest device
/// with the weakest lock gets the fewest capabilities.
///
/// It holds its own copy of the secrets rather than asking the phone for a code, because
/// it has to work with the phone off, absent, or out of range. The copies arrive through
/// iCloud Keychain, in the access group both targets declare, rather than over
/// WatchConnectivity, which would mean building a second transport for secret material to
/// leak through.
@main
struct OpenFactorWatchApp: App {

    /// The same store the phone uses, with the same defaults.
    ///
    /// No access group is named here, for the same reason as on the phone: the entitlement
    /// declares exactly one and the Keychain uses the first entry as the default. The watch
    /// declares the same group, which is the whole mechanism by which it sees the phone's
    /// accounts.
    ///
    /// It is constructed device only and unsynchronized because the watch never writes.
    /// Those two settings only affect items this store adds, and this store adds nothing.
    private let store = KeychainSecretStore()

    var body: some Scene {
        WindowGroup {
            WatchAccessProofView(store: store)
        }
    }
}
