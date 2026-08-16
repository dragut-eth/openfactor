import OpenFactorCore
import SwiftUI

/// Stands between the app lock and the account list, and shows one of three things.
///
/// The account list is only built when the vault is open. It is not drawn behind a cover and it
/// is not drawn with empty rows: a list that renders while the key is missing would show every
/// account as unreadable, which is a true statement about the storage and a frightening and
/// wrong one about the person's accounts.
///
/// The state is re-read whenever the app comes forward, so a wrapped record that arrives from
/// iCloud while the setup screen is open moves the device to the unlock question on its own.
/// That is the difference between somebody waiting a few minutes and somebody creating a second
/// vault that strands the first.
struct VaultGateView<Content: View>: View {

    @State private var model: VaultGateModel

    let store: any SecretStore

    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    init(vault: Vault, store: any SecretStore, @ViewBuilder content: @escaping () -> Content) {
        _model = State(initialValue: VaultGateModel(vault: vault))
        self.store = store
        self.content = content
    }

    var body: some View {
        Group {
            switch model.stage {
            case .checking:
                // Blank rather than a spinner. Reading a file and one Keychain item takes no
                // measurable time, and a spinner that appears for one frame at every launch is
                // worse than nothing appearing at all.
                Color(.systemBackground).ignoresSafeArea()
            case .introducing, .showingPassphrase:
                VaultSetupView(model: model)
            case .locked:
                VaultUnlockView(model: model, store: store)
            case .open:
                content()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            model.refresh()
        }
        #if DEBUG
            // Offered from here rather than built in Settings, because only the gate holds the
            // state that has to be re-read afterwards. Settings would delete everything and
            // leave the account list standing in front of a vault that no longer exists.
            .environment(\.debugForgetEverything) { model.forgetEverything(in: store) }
            .environment(\.debugLockDevice) { model.lockForDebug() }
        #endif
    }

}

#if DEBUG
    extension EnvironmentValues {
        /// Set by `VaultGateView` in Debug builds only. `nil` everywhere else, which is what
        /// Settings keys the row's existence off, so there is nothing to hide in a release
        /// build and nothing to accidentally leave switched on.
        @Entry var debugForgetEverything: (() -> Void)?

        /// Also Debug only. Drops the key and keeps the accounts, which is the one state that
        /// cannot otherwise be reached on a phone that is already set up.
        @Entry var debugLockDevice: (() -> Void)?
    }
#endif
