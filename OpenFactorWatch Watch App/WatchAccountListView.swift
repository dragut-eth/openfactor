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
                        // Identity per account, or SwiftUI reuses the same destination
                        // instance between pushes and the previous account's code stays on
                        // screen until the next refresh lands. Showing one account's code
                        // under another account's name is worse than a slow screen: it is
                        // the kind of thing someone types into the wrong login.
                        WatchCodeView(store: store, record: record)
                            .id(record.id)
                    } label: {
                        row(record)
                    }
                    // A hint of the account's colour rather than a column of identical grey
                    // slabs. Mostly black, so the issuer drawn in the full strength colour
                    // on top of it stays legible. Both ends are asserted by test.
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WatchPalette.rowBackground(for: record.metadata.color).color)
                            .opacity(WatchList.needsPhone(record) ? 0.6 : 1)
                    )
                }

                if rows.contains(where: WatchList.needsPhone) {
                    phoneFootnote
                }
            }
            // No title. The app's name at the top of its own list is a word the wearer
            // already knows, spending the most valuable strip of a very small screen.
        }
        .task(id: scenePhase) { load() }
    }

    /// A row, dimmed and marked when its code lives on the phone.
    ///
    /// The glyph carries the meaning and the dimming carries the ranking. Sixty percent is
    /// the weight the system gives `.secondary`, which is the same claim being made here:
    /// still readable, not what you came for. It is applied to the whole row rather than to
    /// the issuer alone, so the colour relationship the palette was checked for is scaled
    /// rather than rearranged.
    private func row(_ record: AccountRecord) -> some View {
        let needsPhone = WatchList.needsPhone(record)

        return HStack(spacing: 4) {
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

            if needsPhone {
                Spacer(minLength: 0)
                Image(systemName: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .accessibilityLabel("On iPhone")
            }
        }
        .opacity(needsPhone ? 0.6 : 1)
        .padding(.vertical, 2)
    }

    /// One line, because a dimmed row and a small glyph are a hint rather than a sentence.
    ///
    /// It appears only when there is something for it to explain, and it says where the
    /// code is rather than that this one is unavailable. "Unavailable" reads as breakage;
    /// naming the phone tells the wearer what to do next, which is the same wording the
    /// code screen uses for the same reason.
    private var phoneFootnote: some View {
        Text("Counter based codes advance on your iPhone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
    }

    /// **This wording is load bearing, and the first version of it was wrong.**
    ///
    /// An empty watch and a broken watch look identical. The original text assumed the
    /// accounts were merely in flight and told the wearer to give it time, because iCloud
    /// Keychain took close to half an hour to carry seven accounts across during PR 14.
    ///
    /// Running gate A2's experiment produced the other cause and caught the mistake: with
    /// sync turned off on the phone, the watch empties within about fifteen minutes, and
    /// "give it time" is then advice to wait for something that will never arrive. The
    /// watch cannot tell the two apart, since both are an empty Keychain, so it names both
    /// rather than confidently giving the wrong one.
    ///
    /// It still must not send someone to re-check settings that are already correct, which
    /// is why waiting is named first: it is the likelier case for a new user, and the one
    /// that resolves itself.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No accounts yet")
                .font(.headline)

            Text(
                """
                Accounts arrive from your iPhone through iCloud Keychain, which can take \
                half an hour the first time. If you just turned sync on, give it time.

                If you have been using OpenFactor here already, check that iCloud sync is \
                still on in OpenFactor on your iPhone. Turning it off empties this watch.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func load() {
        do {
            rows = WatchList.ordered(try store.records().readable)
            failure = nil
        } catch {
            rows = []
            failure = "Your accounts could not be read. Unlock your watch and try again."
        }
    }
}
