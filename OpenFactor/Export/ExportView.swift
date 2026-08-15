import OpenFactorCore
import SwiftUI

/// Exporting every account into one encrypted file.
///
/// Three screens, and the middle one is the point: the passphrase exists, is shown, and has
/// to be acknowledged before any file is written. A backup whose passphrase was never read
/// is not a backup, it is a file nobody can open.
struct ExportView: View {

    @State private var model: ExportViewModel

    @Environment(\.dismiss) private var dismiss

    init(store: any SecretStore) {
        _model = State(initialValue: ExportViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .explaining: explanation
                case .choosing: passphrase
                case let .ready(url): ready(url)
                case let .failed(message): failure(message)
                }
            }
            .navigationTitle("Export accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel until a file exists, Done after, the same rule the import sheet
                // follows. Nothing has left the app until the share sheet is used.
                if case .ready = model.stage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        // Whichever way the screen goes away. The app keeps no history of exports.
        .onDisappear { model.discardFile() }
    }

    // MARK: - What the file is

    private var explanation: some View {
        Form {
            Section {
                Button("Continue") {
                    Task { await model.authenticate() }
                }
            } header: {
                Text("An encrypted archive")
            } footer: {
                // Said before anything is generated, because after the file exists the
                // decision has already been made.
                Text(
                    """
                    The archive holds every account you have, encrypted with a passphrase \
                    OpenFactor generates. Keeping it somewhere safe is your job: anyone who \
                    has both the file and the passphrase has all of your codes.

                    OpenFactor will ask you to confirm it is you before it starts.
                    """
                )
            }

            Section {
                LabeledContent("Format", value: "openfactor.backup.v1")
                LabeledContent("Encryption", value: "AES-256-GCM")
                LabeledContent("Key derivation", value: "PBKDF2-HMAC-SHA256")
            } footer: {
                // Named, rather than described as "strong encryption", because the whole
                // premise of the format is that somebody else's software can open the file.
                // The full specification is in the repository, and a person who wants to
                // write their own reader needs the names to start from.
                Text(
                    """
                    The format is documented so that another program, written by someone \
                    else, can open this file. A backup you can only open with the app that \
                    wrote it is not a backup.
                    """
                )
            }
        }
    }

    // MARK: - The passphrase

    private var passphrase: some View {
        Form {
            Section {
                Picker("Passphrase", selection: $model.choice) {
                    Text("Generated").tag(ExportViewModel.PassphraseChoice.generated)
                    Text("Your own").tag(ExportViewModel.PassphraseChoice.own)
                }
                .pickerStyle(.segmented)
            }

            if model.choice == .generated {
                generatedPassphrase
            } else {
                ownPassphrase
            }

            Section {
                Toggle("I have saved this passphrase", isOn: $model.hasSavedPassphrase)
            } footer: {
                // The one sentence on this screen that has to be believed. There is no
                // recovery path, no reset, and no copy held anywhere: that is the property
                // that makes the archive safe to store, and the same property that makes
                // losing the passphrase final.
                Text(
                    """
                    OpenFactor does not keep a copy. If this passphrase is lost, the archive \
                    cannot be opened by anyone, including you.
                    """
                )
            }

            Section {
                Button("Create archive") { model.export() }
                    .disabled(!model.canExport)
            } footer: {
                if model.accountCount > 0 {
                    Text("\(model.accountCount) accounts will be included.")
                }
            }
        }
    }

    private var generatedPassphrase: some View {
        Section {
            Text(model.displayedPassphrase)
                // Monospaced so the groups line up under each other when it wraps, which is
                // how somebody copying it by hand keeps their place.
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

            Button("Copy passphrase") {
                CodeClipboard.copy(passphrase: model.displayedPassphrase)
            }

            Button("Generate a different one") { model.regenerate() }
        } header: {
            Text("Passphrase")
        } footer: {
            Text(
                """
                One hundred and twenty bits, from this device. The letters and digits avoid \
                every pair that is easy to confuse by hand, and the hyphens are there to be \
                read rather than typed: they are not part of the passphrase.
                """
            )
        }
    }

    private var ownPassphrase: some View {
        Section {
            SecureField("Your passphrase", text: $model.ownPassphrase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !model.ownPassphrase.isEmpty, let advice = model.ownPassphraseAssessment.advice {
                Text(advice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Passphrase")
        } footer: {
            // The honest version, which the format document arrived at only after an earlier
            // revision claimed the choice of key derivation made no difference here. It
            // does: this is the path where PBKDF2's universal availability is paid for.
            Text(
                """
                A passphrase you choose is easier to guess than one this device generates, \
                and the guessing happens on someone else's computer at whatever speed they \
                can afford. Four or five unrelated words are far better than one word with \
                digits after it.
                """
            )
        }
    }

    // MARK: - The file

    private func ready(_ url: URL) -> some View {
        Form {
            Section {
                ShareLink(item: url) {
                    Label("Save the archive", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Ready")
            } footer: {
                Text(
                    """
                    Save it somewhere you will still have it when this phone is gone. \
                    OpenFactor keeps no copy and no record that you made one.
                    """
                )
            }

            Section {
                LabeledContent("File", value: url.lastPathComponent)
                LabeledContent("Accounts", value: "\(model.accountCount)")
            }
        }
    }

    private func failure(_ message: String) -> some View {
        Form {
            Section { Text(message) }
        }
    }
}
