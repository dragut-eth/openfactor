import OpenFactorCore
import SwiftUI
import UniformTypeIdentifiers

/// Importing accounts from another app's export.
///
/// Four states, and the middle one is the point: nothing is written until the person has
/// seen what the file holds and said yes.
struct ImportView: View {

    @State private var model: ImportViewModel
    @State private var isPickingFile = false
    @State private var includeConflicts = false
    @State private var passphrase = ""

    /// Called when accounts have been written, so whatever is behind can reload. **Not a
    /// signal to close.** Conflating the two is what hid the finish screen on the transfer
    /// path: the caller dismissed the whole add sheet the instant Add was tapped, taking
    /// this screen with it, so the line telling somebody they had scanned one part of three
    /// was written, tested and never once displayed.
    private let onImported: () -> Void

    /// Called when the person is finished with this screen, for a caller that has more to
    /// tear down than this sheet. `nil` means dismissing this one is the whole job.
    private let onFinished: (() -> Void)?

    private let origin: Origin

    @Environment(\.dismiss) private var dismiss

    /// How the accounts got here, which changes only what the last screen says.
    ///
    /// The preview itself does not care: the same three dispositions, the same refusals,
    /// the same rule that nothing is written until somebody agrees. What differs is the
    /// advice at the end. A file holding secret keys should be deleted; a transfer that was
    /// one of three has two codes still to scan.
    enum Origin: Equatable {
        case file
        case transfer(part: Int, of: Int)
    }

    init(store: any SecretStore, onImported: @escaping () -> Void) {
        _model = State(initialValue: ImportViewModel(store: store))
        self.onImported = onImported
        self.onFinished = nil
        self.origin = .file
    }

    /// Opens with something the system handed the app: a file through "Open in OpenFactor", or
    /// bytes the share extension left in the group container.
    init(
        store: any SecretStore,
        arrival: InboxOpener.Arrival,
        onImported: @escaping () -> Void
    ) {
        let model = ImportViewModel(store: store)
        switch arrival {
        case let .data(data): model.read(data)
        case let .file(url): model.read(url)
        }

        _model = State(initialValue: model)
        self.onImported = onImported
        self.onFinished = nil
        self.origin = .file
    }

    /// Opens straight into the preview, for accounts that arrived from a scanned transfer.
    init(
        store: any SecretStore,
        batch: GoogleAuthenticatorImport.Batch,
        onImported: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        let model = ImportViewModel(store: store)
        model.present(batch.result, source: "Google Authenticator")

        _model = State(initialValue: model)
        self.onImported = onImported
        self.onFinished = onFinished
        self.origin = .transfer(part: batch.position, of: batch.size)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .choosing: chooser
                case let .locked(_, failure): locked(failure)
                case .unlocking: unlocking
                case let .reviewing(preview): review(preview)
                case let .finished(added, skipped): finished(added: added, skipped: skipped)
                case let .failed(message): failure(message)
                }
            }
            .navigationTitle("Import accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The word follows the stage, because the wrong one here is a data loss
                // bug with a friendly face: "Done" over a preview reads as "the import is
                // finished" when nothing has been written yet, and the one control that
                // writes is at the bottom of the form. Until then leaving is a cancel, and
                // it sits on the leading edge like every other cancel in the app. Once
                // accounts are actually added it becomes Done, on the trailing edge.
                if case .finished = model.stage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onFinished?() ?? dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                // Both readers take text, and the format is decided by looking inside. An
                // export saved under the wrong extension is still that export.
                allowedContentTypes: [.json, .rtf, .plainText, .data]
            ) { result in
                if case let .success(url) = result { model.read(url) }
            }
        }
    }

    private var chooser: some View {
        Form {
            Section {
                Button("Choose a file…") { isPickingFile = true }
            } footer: {
                Text(
                    """
                    OpenFactor can read a backup it exported, a text or RTF export that \
                    lists accounts with **Account Name** and **Secret Key** labels, and an \
                    unencrypted Aegis vault. Nothing is added until you have seen what the \
                    file contains.
                    """
                )
            }
        }
    }

    /// The passphrase screen, which exists only for OpenFactor archives.
    ///
    /// Deliberately says nothing encouraging about how many attempts are left or how close a
    /// passphrase looked, because there is no such information: the reader cannot tell a
    /// wrong passphrase from an altered file, and pretending otherwise on this screen would
    /// be the app's most consequential lie.
    private func locked(_ failure: String?) -> some View {
        Form {
            Section {
                // Monospaced, like every other field in the app that takes a string a
                // machine generated rather than a person invented: this one, the vault
                // passphrase, and the secret key in manual setup.
                //
                // **Visible, not secured**, and the vault's unlock field matches. Both take 24
                // generated characters copied off a card or out of a password manager, and
                // hiding them means a mistyped character cannot be seen in the one string where
                // the app has already admitted it cannot tell a typo from a wrong passphrase.
                // Shoulder surfing is the cost, and it is a smaller one for something done once
                // per device on a screen that faces its owner.
                TextField("Backup passphrase", text: $passphrase, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { open() }

                Button("Open backup") { open() }
                    .disabled(passphrase.isEmpty)
            } header: {
                Text("This backup is encrypted")
            } footer: {
                // Says which passphrase, the same way the vault's unlock screen does.
                // Somebody who has both holds two strings that look identical, and this screen
                // used to ask for "the passphrase" as though there were only one.
                Text(
                    """
                    The passphrase OpenFactor showed you when you created this backup. This is \
                    not your vault passphrase.

                    Dashes, spacing and capitalization do not matter.
                    """
                )
            }

            if let failure {
                Section {
                    Text(failure).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var unlocking: some View {
        VStack(spacing: 12) {
            ProgressView()
            // Named rather than left as a spinner, because the wait is deliberate: it is
            // the work factor that makes guessing the passphrase expensive, and a person
            // who knows that is not a person watching an app hang.
            Text("Deriving the key. This takes a moment on purpose.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func open() {
        guard !passphrase.isEmpty else { return }
        Task { await model.unlock(with: passphrase) }
    }

    private func review(_ preview: ImportViewModel.Preview) -> some View {
        Form {
            Section {
                LabeledContent("Found in", value: preview.source)
                LabeledContent("Will be added", value: "\(preview.importable.count)")

                if !preview.duplicates.isEmpty {
                    LabeledContent("Already here", value: "\(preview.duplicates.count)")
                }
                if !preview.conflicts.isEmpty {
                    LabeledContent("Conflicting", value: "\(preview.conflicts.count)")
                }
                if !preview.refusals.isEmpty {
                    LabeledContent("Cannot be read", value: "\(preview.refusals.count)")
                }
            }

            if !preview.importable.isEmpty {
                Section("Will be added") {
                    ForEach(preview.importable) { candidate in
                        row(candidate)
                    }
                }
            }

            if !preview.conflicts.isEmpty {
                Section {
                    ForEach(preview.conflicts) { candidate in
                        row(candidate)
                    }
                    Toggle("Add these anyway", isOn: $includeConflicts)
                } header: {
                    Text("Conflicting")
                } footer: {
                    // The distinction gate A3's second review insisted on. The same secret
                    // with different settings is a different authenticator, and only the
                    // user knows which is right.
                    Text(
                        """
                        You already have these secrets, but with different settings, so \
                        they would generate different codes. Only you can tell which is \
                        correct.
                        """
                    )
                }
            }

            if !preview.duplicates.isEmpty {
                Section {
                    ForEach(preview.duplicates) { candidate in
                        row(candidate)
                    }
                } header: {
                    Text("Already here")
                } footer: {
                    Text("Skipped, because you already have these exactly as they are.")
                }
            }

            if !preview.refusals.isEmpty {
                Section {
                    ForEach(preview.refusals, id: \.position) { refusal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refusal.label ?? "Account \(refusal.position)")
                                .font(.body)
                            Text(refusal.reason.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Cannot be read")
                } footer: {
                    Text(
                        """
                        These stay in the other app. Nothing else in the file is affected \
                        by them.
                        """
                    )
                }
            }

            Section {
                Button("Add \(countToAdd(preview)) accounts") {
                    model.confirm(preview, includingConflicts: includeConflicts)
                    onImported()
                }
                .disabled(countToAdd(preview) == 0)
            }
        }
    }

    private func countToAdd(_ preview: ImportViewModel.Preview) -> Int {
        preview.importable.count + (includeConflicts ? preview.conflicts.count : 0)
    }

    private func row(_ candidate: ImportViewModel.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.label)
            if !candidate.imported.account.name.isEmpty,
                candidate.imported.account.issuer != nil {
                Text(candidate.imported.account.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func finished(added: Int, skipped: Int) -> some View {
        Form {
            Section {
                Text("\(added) added.")
                if skipped > 0 {
                    Text("\(skipped) skipped.").foregroundStyle(.secondary)
                }
            } footer: {
                finishedAdvice
            }
        }
    }

    @ViewBuilder
    private var finishedAdvice: some View {
        switch origin {
        case .file:
            // The file the user just imported from is a plaintext list of every secret it
            // held. Saying so is the last useful thing this screen can do.
            Text(
                """
                That file contains your secret keys in the clear. Delete it when you no \
                longer need it.
                """
            )

        case let .transfer(part, total) where total > 1:
            // The line that replaces a whole collecting screen. The scanned code says which
            // part of how many it is, so rather than holding partial state across scans and
            // tracking what is missing, the app reads the field it already parsed and says
            // it. Somebody who stops here has been told they are not finished.
            Text(
                """
                That was part \(part) of \(total). Scan the other codes to bring the rest \
                across. Accounts you already have will be skipped.
                """
            )

        case .transfer:
            Text("Your accounts are still in the other app. Nothing there was changed.")
        }
    }

    private func failure(_ message: String) -> some View {
        Form {
            Section {
                Text(message)
            }
            Section {
                Button("Choose a different file") { isPickingFile = true }
            }
        }
    }
}
