import OpenFactorCore
import SwiftUI

/// Settings.
///
/// **Only what works appears here.** The roadmap has rows coming for iCloud sync, an app
/// lock, and export, and none of them are in this list, because a settings screen is a
/// description of what an app does. A row saying "App Lock" tells a reader their codes
/// are behind Face ID, and a disabled row saying "coming soon" tells them the app is
/// nearly there. Neither is true today, and for a security tool that is not a harmless
/// exaggeration. The rows arrive with the features.
struct SettingsView: View {

    @AppStorage(PreferenceKey.sortOrder) private var sortOrder = AccountSortOrder.manual.rawValue
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearancePreference.system.rawValue
    @AppStorage(PreferenceKey.syncEnabled) private var syncEnabled = false

    @State private var syncFailure: String?

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
                    Your accounts are in iCloud Keychain, which is end to end encrypted. \
                    Apple cannot read them. Turning this off keeps them on this device and \
                    stops them reaching your other ones.
                    """
                    : """
                    Puts your accounts in iCloud Keychain so they reach your other devices, \
                    including Apple Watch. It is end to end encrypted and Apple cannot read \
                    it. In exchange, your accounts become readable whenever this device is \
                    unlocked rather than only on this device, because a synced item cannot \
                    be device only.
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
                } catch {
                    syncFailure = Self.message(for: error)
                }
            }
        )
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
            // It changes with the sync switch on purpose. "On this device only" was true
            // before sync existed and became a lie the moment someone turned it on, and a
            // security claim that quietly stops being true is worse than none at all.
            Text(
                syncEnabled
                    ? """
                    OpenFactor keeps your accounts in the Keychain and, while sync is on, in \
                    iCloud Keychain. There is no OpenFactor account and no server, and the \
                    app makes no network requests of its own. You can read the source and \
                    check that.
                    """
                    : """
                    OpenFactor stores your accounts on this device only. There is no \
                    OpenFactor account and no server, and the app makes no network requests. \
                    You can read the source and check that.
                    """
            )
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
