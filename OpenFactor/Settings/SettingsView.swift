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
    @AppStorage(PreferenceKey.appIcon) private var appIcon = AppIconPreference.dark.rawValue
    @AppStorage(PreferenceKey.appLockEnabled) private var appLockEnabled = false
    @AppStorage(PreferenceKey.appLockGraceSeconds) private var appLockGrace = AppLockGrace.immediately.rawValue

    /// Set when the toggle was refused because the device cannot authenticate.
    @State private var appLockUnavailable = false

    @State private var syncFailure: String?

    /// Where the accounts actually are, read from the Keychain rather than inferred from
    /// the switch. Gate A2, F12: "on this device only" is the strongest sentence in the
    /// app and it was the one sentence asserted without looking.
    @State private var syncState: SyncState?

    let store: any SecretStore

    #if DEBUG
        @Environment(\.debugForgetEverything) private var forgetEverything
        @Environment(\.debugLockDevice) private var lockDevice
        @State private var isForgetting = false
    #endif

    /// Called after accounts are added or removed here, so the list behind reloads rather
    /// than showing rows that no longer match what is stored.
    var onAccountsChanged: () -> Void = {}

    /// One presentation, not one per section.
    ///
    /// Two `.sheet` modifiers on sibling sections of the same `Form` conflict: SwiftUI
    /// supports one presentation per view, and the second tore the first down the instant
    /// it appeared, taking the settings sheet with it and dropping the user back to the
    /// list. Driving a single sheet from an enum is the shape that does not have that
    /// failure mode.
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case importing
        case exporting
        case erasing

        var id: String { rawValue }
    }

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

                    Picker("App icon", selection: $appIcon) {
                        ForEach(AppIconPreference.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: appIcon) { _, new in
                        AppIconChanger.apply(AppIconPreference(rawValue: new) ?? .dark)
                    }
                } footer: {
                    if sortOrder != AccountSortOrder.manual.rawValue {
                        Text("Cards can only be dragged into a new order while sorting is manual.")
                    }
                }

                appLockSection

                if let syncing = store as? any SynchronizableSecretStore {
                    syncSection(syncing)
                }
                backupSection
                eraseSection
                aboutSection
                #if DEBUG
                    debugSection
                #endif
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .importing:
                    ImportView(store: store) {
                        onAccountsChanged()
                        refreshSyncState()
                    }
                case .exporting:
                    ExportView(store: store)
                case .erasing:
                    EraseAccountsView(store: store) {
                        onAccountsChanged()
                        refreshSyncState()
                    }
                }
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

    private var appLockSection: some View {
        Section {
            Toggle("App Lock", isOn: appLockBinding)

            if appLockEnabled {
                Picker("Require after", selection: $appLockGrace) {
                    ForEach(AppLockGrace.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
        } header: {
            Text("Security")
        } footer: {
            // Honest about what it is. The lock is a gate in front of the interface; the
            // secrets are protected by the device's Keychain with it on or off, and saying
            // otherwise here would be the overclaim SECURITY.md forbids.
            Text(
                appLockUnavailable
                    ? """
                    App Lock needs a device passcode, and this device has none. Set one in \
                    iOS Settings first.
                    """
                    : """
                    Requires Face ID, Touch ID, or your passcode before anything is shown. \
                    Your secrets are protected by this device's Keychain either way; App \
                    Lock keeps codes off the screen when someone else is holding your \
                    unlocked phone.
                    """
            )
        }
    }

    /// Refuses to enable on a device that cannot authenticate, because a lock that cannot
    /// lock is a false claim with a switch on it.
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { wanted in
                if wanted && !AppLockAvailability.canAuthenticate {
                    appLockUnavailable = true
                    return
                }

                appLockUnavailable = false
                appLockEnabled = wanted
            }
        )
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
                    whether anything has arrived elsewhere. Turning this off keeps your \
                    accounts on this iPhone and removes them from your other devices, \
                    including your Apple Watch, until you turn it back on.
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

        // An unreadable sync state must not round down to the reassuring answer. Gate
        // A2, F20.
        if state.hasUnknown {
            return "OpenFactor keeps your accounts in the Keychain. Where some of them "
                + "are is unclear right now. \(common)"
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

    private var backupSection: some View {
        Section {
            Button("Export accounts…") { sheet = .exporting }
            Button("Import accounts…") { sheet = .importing }
        } header: {
            Text("Backup")
        } footer: {
            // Export is named first and described first, because it is the one that has to
            // happen before it is needed. Import reads three things now, and the sentence
            // says which without turning into a list of file extensions.
            Text(
                """
                Export writes every account into one encrypted file, and asks you to confirm \
                it is you first. Import reads that file back, a labeled text export, or an \
                unencrypted Aegis vault. A transfer code from Google Authenticator is \
                scanned with the + button instead.
                """
            )
        }
    }

    /// Its own section, at the bottom, away from anything routine. A destructive action
    /// sharing a section with a colour picker invites the wrong tap.
    private var eraseSection: some View {
        Section {
            Button(role: .destructive) {
                sheet = .erasing
            } label: {
                Text("Erase all accounts")
            }
        } footer: {
            Text(
                """
                Removes every account from this iPhone. Deleting the app does not do this, \
                because the Keychain outlives it.
                """
            )
        }
    }

    #if DEBUG
        /// A development affordance, and one that does not exist in any other build.
        ///
        /// The setup screen can otherwise be read once per device and never again, which makes
        /// working on its wording a loop of deleting the app, reinstalling, and starting over.
        /// The row is keyed off the environment value the vault gate sets, so a release build
        /// has nothing to hide: the closure is absent and the section renders nothing.
        ///
        /// A confirmation, but no Face ID. The point is to be fast, and the thing this protects
        /// is a developer's test data. The real erase is untouched and still authenticates.
        /// Reads the wrapped record's own sync flag, for a device under test.
        static func wrappedKeyReport() -> String {
            guard let report = WrappedKeyStore().syncReport() else { return "none on this device" }

            let place = report.isSynchronizable ? "in iCloud" : "this device only"
            let counted = report.records == 1 ? place : "\(place), \(report.records) records"

            // **The flag alone can say the wrong thing.** A record written with the flag set and a
            // device-only protection class reads as "in iCloud" here while iCloud can never carry
            // it. Saying so is what lets a device under test answer whether it is affected.
            return report.protectionMatchesFlag ? counted : "\(counted), class does not match"
        }

        @ViewBuilder
        private var debugSection: some View {
            if let forget = forgetEverything {
                Section {
                    // **The one boolean two findings turned on and nobody could see.** S1-1 was
                    // the wrapped key never syncing while every account did; S1-13 is the repair
                    // for devices already in that state failing in silence. A record count above
                    // one is the twin case, S1-12. Debug only: an instrument for testing recovery
                    // on real devices, not something to explain to anybody.
                    LabeledContent("Wrapped key", value: Self.wrappedKeyReport())

                    if let lockDevice {
                        // Not destructive, and no confirmation, because nothing is lost: the
                        // accounts stay sealed and the passphrase still opens them. It exists
                        // so the unlock screen can be looked at at all, which on a phone that
                        // is already set up otherwise needs a second device.
                        Button("Lock this iPhone") {
                            lockDevice()
                            dismiss()
                        }
                    }

                    Button(role: .destructive) { isForgetting = true } label: {
                        Text("Forget everything")
                    }
                    .confirmationDialog(
                        "Forget everything?",
                        isPresented: $isForgetting,
                        titleVisibility: .visible
                    ) {
                        Button("Forget everything", role: .destructive) {
                            forget()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Accounts, the vault, and every preference.")
                    }
                } header: {
                    Text("Debug build only")
                } footer: {
                    Text(
                        """
                        Lock drops this device's key and keeps the accounts, which is the \
                        unlock screen. Forget everything returns this iPhone to an install that \
                        has never been run. Neither is present in a release build.
                        """
                    )
                }
            }
        }
    #endif

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.version)

            Link(destination: Self.repository) {
                Label("Source code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Link(destination: Self.repository.appending(path: "blob/main/LICENSE")) {
                Label("License", systemImage: "doc.text")
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
