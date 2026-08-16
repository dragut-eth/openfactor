import OpenFactorCore
import SwiftUI

/// The two screens a device sees before it has a vault: what one is, and the passphrase.
///
/// Nothing is stored until the second screen's toggle is on and its button is pressed. Leaving
/// before that point leaves the device exactly as it was found.
struct VaultSetupView: View {

    @Bindable var model: VaultGateModel

    var body: some View {
        NavigationStack {
            Group {
                if case let .showingPassphrase(generated) = model.stage {
                    passphrase(generated)
                } else {
                    introduction
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        if case .showingPassphrase = model.stage { return "Your vault passphrase" }
        return "Set up OpenFactor"
    }

    // MARK: - What a vault is

    private var introduction: some View {
        Form {
            // Deliberately says nothing about iCloud. Sync is off by default, so the first
            // person to read this screen always has it off, and a paragraph about what iCloud
            // carries would be describing something that is not happening. What is true in both
            // configurations is the key and where it lives, so that is what this says. iCloud is
            // explained on the screen that has the switch, where the decision is being made.
            Section {
                Text(
                    """
                    Your accounts are encrypted with a key that never leaves this iPhone. \
                    Anything else that ends up holding them, a backup or another device, holds \
                    them encrypted.
                    """
                )
            }

            Section {
                Button("Create my vault") { model.offerPassphrase() }
            } footer: {
                // It used to say the passphrase was the only way to reach your accounts from a
                // new iPhone. That is false with sync off, where nothing reaches a new iPhone at
                // all. What the passphrase actually does is rebuild the key, and the case that
                // happens in most often is a restore, where the encrypted accounts come back
                // from a backup and the key deliberately does not.
                Text(
                    """
                    OpenFactor will show you a passphrase, once. It is what rebuilds this key if \
                    this iPhone ever loses it, after restoring from a backup for example.
                    """
                )
            }

            // The case this screen most needs to get right, and the one nothing in the state
            // can distinguish: a second device whose wrapped record has not arrived yet looks
            // exactly like a first device. This project measured iCloud Keychain taking close
            // to half an hour. Creating a second vault here would strand every account sealed
            // under the first, so the wait is described rather than left to be discovered.
            //
            // This is the one section that has to name iCloud, because arrival is the thing it
            // is about and arrival only happens with sync on. The condition is stated rather
            // than assumed: somebody whose other iPhone has sync off will wait forever, and
            // telling them to wait would be the same false promise in a politer form.
            //
            // Whether the record arrives does not depend on *this* iPhone's sync setting. The
            // record carries its own synchronizable attribute and the lookup accepts either, so
            // a phone with sync off still sees one that another phone synced.
            Section {
                Button("Check again") { model.refresh() }
            } header: {
                Text("Already using OpenFactor?")
            } footer: {
                Text(
                    """
                    If you already use OpenFactor on another iPhone or iPad with iCloud sync \
                    turned on, your accounts may still be on their way here. iCloud can take up \
                    to an hour. Wait, then check again: this screen will ask for your existing \
                    passphrase once they arrive.

                    Creating a vault now would leave those accounts unreadable.
                    """
                )
            }

            if let failure = model.failure {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - The passphrase

    private func passphrase(_ generated: String) -> some View {
        Form {
            Section {
                grid(generated)

                Button("Copy passphrase") {
                    CodeClipboard.copy(passphrase: BackupPassphrase.grouped(generated))
                }
            } footer: {
                // Named, and named as the vault's. `docs/VAULT.md` requires the two passphrases
                // be distinguishable: this one and an archive's are generated identically and
                // look identical, and somebody recovering months later would hold two strings
                // with nothing to tell them apart.
                Text(
                    """
                    This is your **vault passphrase**. An exported archive has a passphrase of \
                    its own, which is a different string for a different thing, so label them \
                    wherever you keep them.
                    """
                )
            }

            Section {
                Toggle("I have saved this passphrase", isOn: $model.hasSavedPassphrase)
                    .disabled(model.isWorking)
            } footer: {
                // Says what is true rather than what would be reassuring. The earlier wording,
                // "if it is lost, and this iPhone is lost", implied the passphrase alone is
                // enough to recover from a lost phone. That holds only with sync on. With sync
                // off the wrapped record lives on this iPhone and nowhere else, so the phone
                // going means the accounts go, passphrase or not.
                Text(
                    """
                    OpenFactor does not keep a copy and cannot show it again. Nobody can reach \
                    your accounts without it, including you.
                    """
                )
            }

            Section {
                Button {
                    Task { await model.createVault() }
                } label: {
                    HStack {
                        Text("Continue")
                        if model.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!model.hasSavedPassphrase || model.isWorking)

                // Not "Cancel". Nothing has been created yet, so there is nothing to cancel;
                // what this does is throw away a string and offer another. It sits in the form
                // rather than the navigation bar, where its label crowded the title badly enough
                // that the two ran together.
                Button("Show me a different one") { model.discardPassphrase() }
                    .disabled(model.isWorking)

                if let failure = model.failure {
                    Text(failure).foregroundStyle(.red)
                }
            } footer: {
                Text("Nothing has been created yet. Your vault is set up when you continue.")
            }
        }
    }

    /// The same shape the export screen uses, for the same reason: six groups of four, read
    /// left to right, so a transcription can be checked group by group.
    private func grid(_ generated: String) -> some View {
        let groups = BackupPassphrase.groups(generated)
        let rows = stride(from: 0, to: groups.count, by: 3).map {
            Array(groups[$0..<min($0 + 3, groups.count)])
        }

        return Grid(horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, group in
                        Text(group)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vault passphrase")
        // Spelled out, because VoiceOver reads a run of letters as a word it invents and this
        // is a string that has to be transcribed exactly.
        .accessibilityValue(generated.map(String.init).joined(separator: " "))
    }
}
