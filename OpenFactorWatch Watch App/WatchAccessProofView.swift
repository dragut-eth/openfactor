import OpenFactorCore
import SwiftUI

/// **Temporary. This screen exists to answer one question and will be deleted.**
///
/// The whole watch design rests on an assumption nobody has tested: that a watchOS app
/// declaring the same `keychain-access-groups` entitlement actually sees the items iCloud
/// Keychain carried over from the phone. `docs/ARCHITECTURE.md` has recorded it as
/// unverified since PR 5, and PR 14 was told to prove it before building anything on top.
///
/// So the first thing the watch app does is read, and say exactly what it found. Building
/// the real list first would have meant discovering the answer through an empty screen with
/// several possible causes.
///
/// It shows issuers and never a code, because a screen made for a photograph in a bug
/// report should not have a working second factor on it.
struct WatchAccessProofView: View {

    let store: any SecretStore

    /// What the read found, or why it did not.
    ///
    /// The failure is text rather than the error, because reading through an existential
    /// widens the typed throw and the only use for it here is to be shown.
    private enum Outcome {
        case found(StoredRecords)
        case failed(String)
    }

    @State private var result: Outcome?

    /// Reads again whenever the app comes back to the front. A `task` runs once, so the
    /// screen kept reporting the world as it was at first launch, which cost a round of
    /// debugging and nearly sent the blame to the Keychain.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keychain access")
                    .font(.headline)

                switch result {
                case .none:
                    Text("Reading...")

                case let .failed(message):
                    Text("Failed")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.footnote)

                case let .found(records):
                    Text("\(records.readable.count) readable")
                        .foregroundStyle(records.readable.isEmpty ? .orange : .green)

                    if !records.unreadable.isEmpty {
                        Text("\(records.unreadable.count) not understood")
                            .foregroundStyle(.orange)
                    }

                    if records.readable.isEmpty {
                        Text(
                            """
                            Nothing here yet. Either iCloud Keychain has not carried the \
                            accounts over, or the access group is not shared after all.
                            """
                        )
                        .font(.footnote)
                    }

                    ForEach(records.readable, id: \.id) { record in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(record.metadata.displayIssuer)
                                .font(.footnote)
                            Text(placements[record.id].map {
                                "\($0.groupSuffix) | \($0.synchronized ? "synced" : "local")"
                            } ?? "no placement")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: scenePhase) { read() }
    }

    @State private var placements: [UUID: ItemPlacement] = [:]

    private func read() {
        do {
            result = .found(try store.records())
        } catch {
            result = .failed(String(describing: error))
        }

        placements = (try? (store as? KeychainSecretStore)?.placements()) as? [UUID: ItemPlacement] ?? [:]
    }
}
