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
            Text(
                """
                OpenFactor stores your accounts on this device only. There is no OpenFactor \
                account and no server, and the app makes no network requests. You can read \
                the source and check that.
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
    SettingsView()
}
