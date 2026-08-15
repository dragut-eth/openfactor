import OpenFactorCore
import SwiftUI

/// Settings.
///
/// **Only what works appears here.** The roadmap has rows coming for an app lock and for
/// export, and neither is in this list, because a settings screen is a description of what
/// an app does. A row saying "App Lock" tells a reader their codes are behind Face ID, and
/// a disabled row saying "coming soon" tells them the app is nearly there. Neither is true
/// today, and for a security tool that is not a harmless exaggeration. The rows arrive with
/// the features, which is how the sync row arrived in PR 13.
///
/// The same rule applies inside a row's own text. The sync footer named Apple Watch before
/// there was a watch app, which taught a reader that their watch already held their
/// secrets. Gate A2 called that an aspirational footer, and it was right.
struct SettingsView: View {

    @AppStorage(PreferenceKey.sortOrder) private var sortOrder = AccountSortOrder.manual.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.syncEnabled) private var syncEnabled = false

    @State private var syncFailure: String?

    /// Where the accounts actually are, read from the Keychain rather than inferred from
    /// the switch. Gate A2, F12: "on this device only" is the strongest sentence in the
    /// app and it was the one sentence asserted without looking.
    @State private var syncState: SyncState?

    let store: any SecretStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private static let repository = URL(string: "https://github.com/dragut-eth/openfactor")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sort accounts", selection: $sortOrder) {
                        ForEach(AccountSortOrder.allCases) { Text($0.label).tag($0.rawValue) }
                    }

                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } footer: {
                    if sortOrder != AccountSortOrder.manual.rawValue {
                        Text("Cards can only be dragged into a new order while sorting is manual.")
                    }
                }

                if let syncing = store as? any SynchronizableSecretStore {
                    syncSection(syncing)
                }
                aboutSection
            }
            .task { refreshSyncState() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func syncSection(_ store: any SynchronizableSecretStore) -> some View {
        Section {
            Toggle("iCloud sync", isOn: syncBinding(store))

            if let syncFailure {
                Text(syncFailure).foregroundStyle(.red)
            }
        } header: {
            Text("Sync")
        } footer: {
            // The one feature that lets secret material off the device, so it explains
            // itself rather than being a switch with a name. Both halves are true and both
            // matter: Apple genuinely cannot read it, and it genuinely weakens how the
            // secrets are protected on this device.
            Text(
                syncEnabled
                    ? """
                    Your accounts are offered to iCloud Keychain, which is end to end \
                    encrypted. Apple cannot read them. This requires iCloud Keychain to be \
                    on in iOS Settings, and OpenFactor cannot check whether it is or \
                    whether anything has arrived elsewhere. Turning this off stops this \
                    device offering them. It may also remove them from your other devices, \
                    which is not something OpenFactor controls.
                    """
                    : """
                    Offers your accounts to iCloud Keychain, so they reach the other \
                    devices signed in to your Apple Account where OpenFactor is installed, \
                    without anyone doing anything on those devices. It is end to end \
                    encrypted and Apple cannot read it, and it requires iCloud Keychain to \
                    be on in iOS Settings. In exchange, your accounts become readable \
                    whenever this device is unlocked rather than only on this device, \
                    because a synced item cannot be device only.
                    """
            )
        }
    }

    private func syncBinding(_ store: any SynchronizableSecretStore) -> Binding<Bool> {
        Binding(
            get: { syncEnabled },
            set: { shouldSync in
                do {
                    // The stored accounts are converted first. Flipping the preference
                    // before the work succeeds would leave the switch claiming something
                    // the Keychain does not agree with.
                    try store.setSynchronizable(shouldSync)
                    syncEnabled = shouldSync
                    syncFailure = nil
                    refreshSyncState()
                } catch {
                    syncFailure = Self.message(for: error)
                }
            }
        )
    }

    /// Reads where the accounts are. A failure leaves it unknown rather than guessed, and
    /// the About footer then says nothing about location.
    private func refreshSyncState() {
        guard let store = store as? any SynchronizableSecretStore else {
            syncState = nil
            return
        }

        syncState = try? store.syncState()
    }

    /// Conversion runs account by account, so a failure part way through leaves some
    /// converted and some not. Saying "nothing changed" would be a comforting lie. The
    /// operation is idempotent, so the honest advice really is to try again.
    private static func message(for error: any Error) -> String {
        if case SecretStoreError.deviceLocked = error {
            return "Unlock your device and try again."
        }
        return "Sync could not be changed. Some accounts may not have moved, so try again."
    }

    /// Says where the accounts are, in the order of how surprising it is.
    ///
    /// The mixed case is not an error to be repaired. It is what a half finished
    /// conversion looks like and also what a device holds when an account arrives from
    /// elsewhere, and the reasoning for describing rather than repairing is in
    /// `SECURITY.md`. Not knowing is its own case: better to say nothing about location
    /// than to assert the strongest claim in the app on a failed query.
    static func storageSummary(_ state: SyncState?) -> String {
        let common =
            "There is no OpenFactor account and no server, and the app makes no network "
            + "requests of its own. You can read the source and check that."

        guard let state else {
            return "OpenFactor keeps your accounts in the Keychain. \(common)"
        }

        if state.isMixed {
            return "Some of your accounts are in iCloud Keychain and some are on this "
                + "device only. \(common)"
        }

        if state.synced.isEmpty {
            return "OpenFactor stores your accounts on this device only. \(common)"
        }

        return "Your accounts are in iCloud Keychain as well as on this device. \(common)"
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.version)

            Link(destination: Self.repository) {
                Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Link(destination: Self.repository.appending(path: "blob/main/LICENSE")) {
                Label("Licence", systemImage: "doc.text")
            }

            Link(destination: Self.repository.appending(path: "issues")) {
                Label("Report an issue", systemImage: "exclamationmark.bubble")
            }
        } header: {
            Text("About")
        } footer: {
            // The one claim this screen makes, and it is checkable rather than
            // reassuring: the source is right there.
            //
            // It describes where the accounts are, read from the Keychain, not where the
            // switch says they should be. Those disagree more often than they look like
            // they would: a conversion can fail part way, and an account synced from
            // another device arrives here whatever this device's switch says. Gate A2, F12.
            Text(Self.storageSummary(syncState))
        }
    }

    /// Version and build, read from the bundle rather than written down twice.
    private static var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return [short, build.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

#Preview {
    SettingsView(store: InMemorySecretStore())
}
