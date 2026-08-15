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

    private let onImported: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(store: any SecretStore, onImported: @escaping () -> Void) {
        _model = State(initialValue: ImportViewModel(store: store))
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .choosing: chooser
                case let .reviewing(preview): review(preview)
                case let .finished(added, skipped): finished(added: added, skipped: skipped)
                case let .failed(message): failure(message)
                }
            }
            .navigationTitle("Import accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                // Both readers take text, and the format is decided by looking inside. A
                // Step Two export saved as .txt is still a Step Two export.
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
                    OpenFactor can read a Step Two export and an unencrypted Aegis vault. \
                    Nothing is added until you have seen what the file contains.
                    """
                )
            }
        }
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
                // The file the user just imported from is a plaintext list of every secret
                // it held. Saying so is the last useful thing this screen can do.
                Text(
                    """
                    That file contains your secret keys in the clear. Delete it when you no \
                    longer need it.
                    """
                )
            }
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
