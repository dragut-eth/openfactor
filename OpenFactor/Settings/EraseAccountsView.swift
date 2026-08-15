import OpenFactorCore
import SwiftUI

/// Erasing every account.
///
/// **Why this exists at all.** Deleting the app does not reliably clear the Keychain, and
/// with sync on anything that did clear comes back from iCloud. Without this there is no
/// way to start over, which matters for someone selling a phone and for anyone testing an
/// import twice.
///
/// **Why it is deliberately slow.** Three defences, and each one is answering a different
/// way this goes wrong. Face ID, because someone holding an unlocked phone should not be
/// able to destroy every second factor with two taps. A typed word, because a confirmation
/// you can tap through is a confirmation you will tap through. And a sentence naming what
/// actually happens, because gate A2 proved that turning sync off empties the watch within
/// fifteen minutes, so an erase certainly does, and that is not obvious from the word
/// "erase" on a phone.
struct EraseAccountsView: View {

    let store: any SecretStore

    /// Called after a successful erase, so the list behind can reload rather than showing
    /// rows for accounts that no longer exist.
    let onErased: () -> Void

    @State private var typed = ""
    @State private var isWorking = false
    @State private var failure: String?
    @State private var syncState: SyncState?

    @Environment(\.dismiss) private var dismiss

    /// The word that has to be typed. Deliberately not "delete", which muscle memory
    /// supplies, and deliberately not localised into something ambiguous.
    private static let confirmation = "ERASE"

    private var isConfirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == Self.confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(warning)
                } header: {
                    Text("This cannot be undone")
                }

                Section {
                    TextField(Self.confirmation, text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } footer: {
                    Text("Type \(Self.confirmation) to confirm.")
                }

                Section {
                    Button(role: .destructive) {
                        Task { await erase() }
                    } label: {
                        HStack {
                            Text("Erase all accounts")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!isConfirmed || isWorking)

                    if let failure {
                        Text(failure).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Erase all accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { syncState = try? (store as? any SynchronizableSecretStore)?.syncState() }
        }
    }

    /// Says what will actually happen, which depends on where the accounts currently are.
    ///
    /// The synced case is not a hypothetical warning: gate A2's experiment showed a paired
    /// watch emptying fourteen minutes after sync was merely switched off. Erasing is more
    /// final than that.
    private var warning: String {
        let base = """
            Every account and every secret is removed from this iPhone. Codes cannot be \
            recovered afterwards, and each service would have to be set up again from \
            scratch.
            """

        guard let syncState, !syncState.synced.isEmpty else { return base }

        return base + """


            Your accounts are in iCloud Keychain, so this also removes them from your \
            other devices, including your Apple Watch.
            """
    }

    /// Authenticates, then erases. Authentication comes first: an unlocked phone in the
    /// wrong hands is exactly the case this is defending against, and App Lock may be off.
    private func erase() async {
        isWorking = true
        defer { isWorking = false }

        guard await AppLockAvailability.authenticate(reason: "Erase all accounts") else {
            failure = "Not erased. Your identity could not be confirmed."
            return
        }

        do {
            let records = try store.records()

            // Every account, including the ones this version cannot decode. Leaving those
            // behind would be the worst outcome: an erase that reports success and leaves
            // secrets on the device.
            for id in records.readable.map(\.id) + records.unreadable {
                try store.delete(id: id)
            }

            onErased()
            dismiss()
        } catch {
            // Partial deletion is possible, so this does not claim nothing happened.
            failure = "Some accounts could not be erased. Open this screen again to retry."
        }
    }
}
