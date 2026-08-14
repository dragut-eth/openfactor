import Combine
import OpenFactorCore
import SwiftUI

/// The root screen: search, the list of cards, and the one timer that drives them all.
struct AccountListView: View {

    @State private var model: AccountListViewModel
    @State private var copied: UUID?

    /// The single timer for the whole screen. Ten accounts do not get ten timers.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(store: any SecretStore) {
        _model = State(initialValue: AccountListViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("OpenFactor")
                .searchable(text: $model.searchText, prompt: "Search accounts")
                .background(Tokens.Surface.background)
                .onAppear { model.load(at: Date()) }
                .onReceive(tick) { model.tick(at: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadFailure = model.loadFailure {
            ContentUnavailableView(
                "Cannot read your accounts",
                systemImage: "exclamationmark.triangle",
                description: Text(loadFailure)
            )
        } else if model.rows.isEmpty && model.unreadable.isEmpty {
            ContentUnavailableView(
                "No accounts yet",
                systemImage: "lock.shield",
                description: Text("Accounts you add will appear here.")
            )
        } else if model.visibleRows.isEmpty && model.isSearching {
            ContentUnavailableView.search
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.Spacing.cardGap) {
                ForEach(model.visibleRows) { row in
                    Button {
                        copy(row)
                    } label: {
                        AccountCard(model: row.card)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if copied == row.id {
                            CopiedBadge()
                        }
                    }
                    .accessibilityHint("Copies the code")
                }

                // Accounts this version cannot read. Shown rather than hidden: an account
                // that silently disappears is one the user thinks they have lost, and its
                // secret is still in the Keychain, intact.
                ForEach(model.unreadable, id: \.self) { id in
                    UnreadableAccountRow(id: id)
                }
            }
            .padding(.horizontal, Tokens.Spacing.medium)
            .padding(.vertical, Tokens.Spacing.small)
        }
    }

    private func copy(_ row: AccountListViewModel.Row) {
        guard model.copyCode(for: row, at: Date()) else { return }

        withAnimation(.snappy) { copied = row.id }

        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.snappy) {
                if copied == row.id { copied = nil }
            }
        }
    }
}

/// The confirmation after a tap. Deliberately does not repeat the code: the point of
/// copying it is that it does not need to be on screen twice.
private struct CopiedBadge: View {
    var body: some View {
        Label("Copied", systemImage: "checkmark")
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(Tokens.Spacing.small)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityHidden(true)
    }
}

/// An account whose stored details this version does not understand.
private struct UnreadableAccountRow: View {
    let id: UUID

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.medium) {
            Image(systemName: "questionmark.folder")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
                Text("An account needs a newer version")
                    .font(Tokens.Text.issuer)

                Text(
                    """
                    Its details were saved by a newer version of OpenFactor. \
                    Its secret is safe and untouched, and updating will show it again.
                    """
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Surface.grouped)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private func previewStore(accounts: [(String, String, AccountColor)]) -> InMemorySecretStore {
    let store = InMemorySecretStore()

    for (issuer, name, color) in accounts {
        try? store.add(
            OTPAccount(
                issuer: issuer,
                name: name,
                secret: Data("12345678901234567890".utf8),
                generator: .totp(.standard)
            ),
            color: color
        )
    }

    return store
}

#Preview("Accounts") {
    AccountListView(
        store: previewStore(accounts: [
            ("Google", "xcany@example.com", .red),
            ("AWS", "Production", .yellow),
            ("Okta", "xcany@example.com", .indigo),
            ("GitHub", "octocat", .gray),
        ])
    )
}

#Preview("Empty") {
    AccountListView(store: InMemorySecretStore())
}
