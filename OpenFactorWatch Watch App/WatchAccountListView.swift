import OpenFactorCore
import SwiftUI

/// The list. Issuer in the account's colour, account name beneath it.
///
/// Not a resized phone card. A card is a coloured rectangle carrying white text, which at
/// this size would be a colour swatch with unreadable writing on it. Here the screen is the
/// black it already is and the colour moves to the type.
///
/// **No code is shown in the list.** The phone shows every code at once because a phone is
/// held deliberately and put away; a watch is on a wrist that is visible to whoever is
/// standing next to you. One code, when you ask for it, is the whole difference.
struct WatchAccountListView: View {

    let store: any SecretStore

    @State private var rows: [AccountRecord] = []
    @State private var failure: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if rows.isEmpty {
                    emptyState
                }

                ForEach(rows, id: \.id) { record in
                    NavigationLink {
                        WatchCodeView(store: store, record: record)
                    } label: {
                        row(record)
                    }
                }
            }
            .navigationTitle("OpenFactor")
        }
        .task(id: scenePhase) { load() }
    }

    private func row(_ record: AccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(record.metadata.displayIssuer)
                .font(.headline)
                .foregroundStyle(WatchPalette.color(for: record.metadata.color))

            if !record.metadata.name.isEmpty {
                Text(record.metadata.name)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    /// **This wording is load bearing.** An empty watch and a broken watch look identical,
    /// and the likeliest reason for an empty one is that sync was turned on a few minutes
    /// ago: iCloud Keychain took close to half an hour to carry seven accounts across during
    /// PR 14, arriving one at a time with no error anywhere.
    ///
    /// So it says what is true, that nothing has arrived, and names the two reasons in the
    /// order they actually occur. It must not send someone off to re-check settings that are
    /// already correct, which is the failure this screen is most likely to cause.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No accounts yet")
                .font(.headline)

            Text(
                """
                Accounts arrive from your iPhone through iCloud Keychain, which can take a \
                while. If you have just turned on iCloud sync in OpenFactor on your iPhone, \
                give it time.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func load() {
        do {
            rows = try store.records().readable
            failure = nil
        } catch {
            rows = []
            failure = "Your accounts could not be read. Unlock your watch and try again."
        }
    }
}
