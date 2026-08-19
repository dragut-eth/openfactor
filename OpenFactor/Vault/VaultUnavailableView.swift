import SwiftUI

/// Shown when the vault's storage could not be read at all.
///
/// **This screen exists to not offer the thing that would destroy the accounts.** The state it
/// replaces was the setup screen, whose button creates a vault, and a Keychain read can fail
/// while a perfectly good wrapped record sits behind it. Creating over that record strands every
/// stored account under a passphrase nobody was ever given. Gate A4 found the collapse that led
/// here: a read failure and an empty store were the same answer.
///
/// So there is one action, and it is to look again. Waiting is always recoverable.
struct VaultUnavailableView: View {

    let model: VaultGateModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)

            Text("Your vault cannot be read")
                .font(.title2)

            Text(
                """
                This iPhone could not reach the place your vault is kept. \
                Nothing has been lost, and nothing has been changed.

                This usually clears on its own. If it does not, restarting your iPhone is the \
                next thing to try.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Try again") { model.refresh() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
