import OpenFactorCore
import SwiftUI

/// The root screen.
///
/// A shell, deliberately. This pull request is about the project structure and the host
/// application that lets the Keychain tests run for real. The card design arrives in
/// PR 6, the live list and countdown in PR 7, and the visual language of both is
/// specified in `docs/UI_SPEC.md`. Nothing here is meant to survive that.
struct AccountListView: View {
    let store: any SecretStore

    @State private var records: [AccountRecord] = []
    @State private var loadFailure: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("OpenFactor")
                .task { load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadFailure {
            ContentUnavailableView(
                "Cannot read your accounts",
                systemImage: "exclamationmark.triangle",
                description: Text(loadFailure)
            )
        } else if records.isEmpty {
            ContentUnavailableView(
                "No accounts yet",
                systemImage: "lock.shield",
                description: Text("Accounts you add will appear here.")
            )
        } else {
            List(records) { record in
                VStack(alignment: .leading) {
                    Text(record.metadata.displayIssuer)
                    Text(record.metadata.name)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Reads metadata only. No secret is decrypted to draw this screen, which is the
    /// property the whole storage design exists to provide.
    private func load() {
        do {
            records = try store.records()
            loadFailure = nil
        } catch {
            records = []
            loadFailure = error.description
        }
    }
}

#Preview("Empty") {
    AccountListView(store: InMemorySecretStore())
}

#Preview("With accounts") {
    let store = InMemorySecretStore()

    for (issuer, name) in [("GitHub", "octocat"), ("AWS", "bandsintown"), ("Okta", "xcany")] {
        try? store.add(
            OTPAccount(
                issuer: issuer,
                name: name,
                secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)
            ),
            color: .suggested(forIssuer: issuer)
        )
    }

    return AccountListView(store: store)
}
