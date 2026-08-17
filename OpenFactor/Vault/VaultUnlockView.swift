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
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vault passphrase", text: $model.typedPassphrase, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .focused($isTyping)
                        .disabled(model.isWorking)
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
            Button(role: .destructive) { isErasing = true } label: {
                Text("Start over")
            }
            .disabled(model.isWorking)
        } header: {
            Text("Lost your passphrase?")
        } footer: {
            Text(
                """
                Without the vault passphrase, this vault cannot be recovered. Starting over \
                removes it from this iPhone and iCloud, then creates a new vault with a new \
                passphrase.

                If you have an exported backup, you can import it after starting over.
                """
            )
        }
    }
}
