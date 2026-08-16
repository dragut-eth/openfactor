import OpenFactorCore
import SwiftUI

/// What the watch shows before it has the key to its own accounts.
///
/// **The list is never drawn without the key.** To the list a watch with no key is a screen full
/// of accounts it cannot read, which would be a true statement about the storage and a
/// frightening and wrong one about somebody's accounts.
///
/// Every state here names what to go and do rather than reporting a fault, because none of them
/// is one: the phone is in another room, or locked, or has not been set up itself.
struct WatchVaultGateView<Content: View>: View {

    @State private var model = WatchVaultModel()

    /// Read to tell a key that works from one that merely exists. See
    /// `WatchVaultModel.refreshAndAsk(in:)`.
    let store: any SecretStore

    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.stage {
            case .checking:
                Color.black.ignoresSafeArea()
            case .ready:
                content()
            case .waiting:
                waiting
            // One message for every way the phone can fail to answer, because the remedy is
            // the same and naming the cause was worse than useless: "iPhone not reachable" also
            // fires when the phone is on the table with the app closed, which reads as a
            // distance problem and sends somebody to check the wrong thing.
            case .needsPhoneApp:
                message(
                    "Open OpenFactor on your iPhone",
                    "Your iPhone needs to be nearby, unlocked, and showing OpenFactor. Then try again.")
            case .phoneNotSetUp:
                message(
                    "Set up your iPhone first",
                    "OpenFactor is not set up on your iPhone yet. Do that first, then set up this watch.")
            case .notSetUp:
                message("Not set up", "Try again when you are ready.")
            case .cannotRead:
                message(
                    "Accounts cannot be read",
                    "This watch has the key but cannot open your accounts. They may need a newer version of OpenFactor.")
            }
        }
        .onAppear { model.activate(in: store) }
        .onChange(of: scenePhase) { _, phase in
            // Coming back is the moment to try again, because every message on this screen asks
            // somebody to go and do something on their phone. They do it, they raise their
            // wrist, and it is already done.
            if phase == .active { model.refreshAndAsk() }
        }
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Waiting for your iPhone")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// A title, a sentence, and the one button. Scrollable because the longest of these does not
    /// fit a small watch at an accessibility text size, and a button that cannot be reached is
    /// the same as no button.
    private func message(_ title: String, _ detail: String) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try again") { model.ask() }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
    }
}
