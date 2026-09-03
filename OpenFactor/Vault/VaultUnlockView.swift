import OpenFactorCore
import SwiftUI

/// The screen a device sees when it holds accounts it cannot read.
///
/// This is the ordinary state of a new iPhone, a restored one, and a reinstall. It is not an
/// error and does not read like one.
struct VaultUnlockView: View {

    @Bindable var model: VaultGateModel

    /// The store, so the way out can delete accounts this device cannot decrypt. `records()`
    /// works without the key and reports every account as unreadable, which is exactly what is
    /// needed to remove them.
    let store: any SecretStore

    @State private var isErasing = false
    @State private var isPassphraseRevealed = false

    @Environment(\.isScreenCaptured) private var isScreenCaptured
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // **Secured, with a reveal**, matching the import screen and the manual
                    // secret field. Audit X2 raised this as OF-A1: a visible field is ordinary
                    // text to iOS, so the keyboard can learn from it, and `.textContentType`
                    // `.password` additionally offered to save this string into iCloud Keychain,
                    // which is where the wrapped record it opens already lives. That content type
                    // is gone; `.oneTimeCode` suppresses the AutoFill offer without claiming the
                    // field is a one time code to anything that matters.
                    //
                    // **Never revealed while the screen is captured**, and disabled rather than
                    // hidden so the reason is visible.
                    HStack {
                        Group {
                            if isPassphraseRevealed && !isScreenCaptured {
                                TextField("Vault passphrase", text: $model.typedPassphrase)
                            } else {
                                SecureField("Vault passphrase", text: $model.typedPassphrase)
                            }
                        }
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .focused($isTyping)
                        .disabled(model.isWorking)

                        Button {
                            isPassphraseRevealed.toggle()
                        } label: {
                            Image(systemName: isPassphraseRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isScreenCaptured || model.isWorking)
                        .accessibilityLabel(
                            isScreenCaptured
                                ? "Showing the passphrase is unavailable while the screen is shared"
                                : (isPassphraseRevealed
                                    ? "Hide the passphrase" : "Show the passphrase"))
                    }
                } footer: {
                    // `docs/VAULT.md` requires the two passphrases be distinguishable where they
                    // are asked for as well as where they are shown. Somebody who exported a
                    // backup holds two strings that look identical, and typing the wrong one
                    // here produces a failure that explains nothing on its own.
                    Text(
                        """
                        This is the vault passphrase OpenFactor gave you when you first set it \
                        up, not the passphrase for an exported backup.

                        Dashes, spacing and capitalization do not matter.
                        """
                    )
                }

                Section {
                    Button {
                        isTyping = false
                        Task { await model.unlock() }
                    } label: {
                        HStack {
                            Text("Unlock")
                            if model.isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.typedPassphrase.isEmpty || model.isWorking)

                    if let failure = model.failure {
                        Text(failure).foregroundStyle(.red)
                    }
                }

                wayOut
            }
            .navigationTitle("Enter your vault passphrase")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { explanation }
            .sheet(isPresented: $isErasing) {
                EraseAccountsView(store: store) {
                    // The vault goes only after the accounts have. The other order would leave
                    // ciphertext with no key anywhere and no way to remove it from this screen,
                    // which is the dead end this whole section exists to prevent.
                    model.destroyVault()
                }
            }
        }
    }

    private var explanation: some View {
        Text(
            """
            Your accounts are here, but this iPhone does not have the key to unlock them. Enter \
            the vault passphrase you saved when you set up OpenFactor.
            """
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    /// **Without this the app is a dead end.** A reinstall with no passphrase can never open its
    /// accounts, cannot reach Settings to erase them, and does not recover by deleting the app,
    /// because the Keychain outlives it and iCloud brings back whatever did clear. So the erase
    /// flow is reachable from here, with its own Face ID and typed word intact.
    private var wayOut: some View {
        Section {
            // **Refused outright when the device has no passcode**, which is a departure from
            // how every other identity check in this app behaves, and audit X2's OF-A4 is where
            // the distinction was drawn.
            //
            // Elsewhere, `AppLockAvailability.authenticate` returning true on a passcode-less
            // device is right: exporting reveals secrets to somebody already holding an unlocked
            // phone with the app open, so the prompt guards data they can read off the screen
            // anyway, and refusing would deny a backup to somebody who is entitled to one.
            //
            // **Here the check prevents something rather than delaying it.** This screen appears
            // only when the device has no key, so whoever is holding it cannot read a single
            // account, and this button is the one action in the app that reaches devices that are
            // not in the room: it removes every account from iCloud, and therefore from the other
            // iPhone and the watch. Without a passcode the only barrier left is a typed word, and
            // a stranger gains a capability they otherwise do not have at all.
            //
            // Disabled rather than hidden, for the reason the manual secret field records: a
            // control that vanishes reads as a bug, and one that does nothing reads as a bug
            // twice. The way out is in the person's own hands and takes half a minute.
            Button(role: .destructive) { isErasing = true } label: {
                Text("Start over")
            }
            .disabled(model.isWorking || !AppLockAvailability.canAuthenticate)
        } header: {
            Text("Lost your passphrase?")
        } footer: {
            if AppLockAvailability.canAuthenticate {
                Text(
                    """
                    Without the vault passphrase, this vault cannot be recovered. Starting over \
                    removes it from this iPhone and iCloud, then creates a new vault with a new \
                    passphrase.

                    If you have an exported backup, you can import it after starting over.
                    """
                )
            } else {
                Text(
                    """
                    **Set a passcode on this iPhone to start over.** Starting over removes your \
                    accounts from iCloud as well, so they disappear from your other devices too, \
                    and OpenFactor will not do that without confirming it is you.

                    Set one in Settings, then come back.
                    """
                )
            }
        }
    }
}
