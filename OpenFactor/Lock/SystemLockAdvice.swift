import SwiftUI

/// What this app says about iOS's own per-app lock, in one place.
///
/// **Two screens offer this and both reach the same sheet**, because two labels for one destination
/// is the drift that took three passes to clean out of this feature's documentation. The button
/// reads "Show Me How" in both.
///
/// **Why an authenticator recommends something it does not own.**
/// `docs/audits/E/E14-the-system-lock-and-the-switcher.md` measured that iOS's per-app Face ID lock
/// removes the app switcher exposure completely and from the first frame, which this app's own
/// cover cannot do: a cover is raised in reaction to a lifecycle event, and the system replaces the
/// snapshot outright. The app had never once mentioned that the lock exists.
///
/// **Nothing here is recorded.** No button sets a preference, and the app cannot detect whether
/// anybody followed the instructions. That is deliberate and `docs/APP_LOCK.md` argues it: acting
/// on the iOS lock would mean storing a claim no API can verify, which goes stale in silence the
/// moment somebody turns the lock off or replaces a phone.
struct SystemLockAdvice: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Go to the Home Screen and hold the OpenFactor icon.",
                        systemImage: "1.circle")
                    Label("Choose Require Face ID.", systemImage: "2.circle")
                } footer: {
                    Text("iOS will ask for Face ID or your passcode before OpenFactor opens.")
                }
            }
            .navigationTitle("Lock OpenFactor with iOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
