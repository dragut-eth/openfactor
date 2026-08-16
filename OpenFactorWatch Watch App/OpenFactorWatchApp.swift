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
/// WatchConnectivity.
///
/// **The one exception is the vault key**, which cannot arrive that way: it never syncs, by
/// design, because a key that syncs is a key in the Keychain. It is asked for once over the
/// interactive WatchConnectivity channel, and `WatchVaultGateView` is what stands in front of
/// the list until it arrives.
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
            #if DEBUG
            // Layout rehearsal, simulator only in practice and DEBUG only by construction.
            //
            // Two things cannot be verified any other way: the watchOS simulator's runtime
            // refuses `simctl ui content_size` outright, and its keychain has no accounts
            // to draw. So `--layout-rehearsal` swaps in an in memory store of fakes, and
            // `--ax-text` pins the largest accessibility size, letting the accessibility
            // layouts be screenshotted before they reach a wrist. Neither flag exists in a
            // release build, and the fakes' secrets are the RFC test vector, which is the
            // one secret on earth that protects nothing.
            if CommandLine.arguments.contains("--layout-rehearsal") {
                let rehearsal = WatchAccountListView(store: Self.rehearsalStore())

                if CommandLine.arguments.contains("--ax-text") {
                    rehearsal.dynamicTypeSize(.accessibility3)
                } else {
                    rehearsal
                }
            } else {
                WatchVaultGateView { WatchAccountListView(store: store) }
            }
            #else
            WatchVaultGateView { WatchAccountListView(store: store) }
            #endif
        }
    }

    #if DEBUG
    private static func rehearsalStore() -> InMemorySecretStore {
        let store = InMemorySecretStore()
        let colors: [AccountColor] = [.red, .teal, .indigo]

        for (index, issuer) in ["GitHub", "Fastmail", "Proton"].enumerated() {
            try? store.add(
                OTPAccount(
                    issuer: issuer,
                    name: "someone@example.com",
                    secret: Data("12345678901234567890".utf8),
                    generator: .totp(.standard)
                ),
                color: colors[index]
            )
        }

        return store
    }
    #endif
}
