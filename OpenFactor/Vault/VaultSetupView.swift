import OpenFactorCore
import SwiftUI

/// The two screens a device sees before it has a vault: what one is, and the passphrase.
///
/// Nothing is stored until the second screen's toggle is on and its button is pressed. Leaving
/// before that point leaves the device exactly as it was found.
struct VaultSetupView: View {

    @Bindable var model: VaultGateModel

    /// Bumped on every copy, which is what drives the haptic and the label. A counter rather
    /// than a flag so copying twice in a row is felt twice.
    @State private var copies = 0
    @State private var hasCopied = false

    var body: some View {
        NavigationStack {
            Group {
                if case let .showingPassphrase(generated) = model.stage {
                    passphrase(generated)
                } else {
                    introduction
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Empty on the intro, where the title is drawn large in the screen itself rather than
    /// shrunk into the bar. A person meeting the app for the first time gets a title; a person
    /// on the second step gets a bar label telling them where they are.
    private var title: String {
        if case .showingPassphrase = model.stage { return "Your vault passphrase" }
        return ""
    }

    // MARK: - What a vault is

    private var introduction: some View {
        Form {
            // A first screen that was a settings form doing a welcome screen's job: grey text
            // and two buttons of equal weight, so nothing said which one was the point. The
            // mark and the large title make it an arrival, and the filled button below makes
            // the primary action look primary.
            Section {
                VStack(spacing: Tokens.Spacing.medium) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Color.accentColor)
                        // The title says it. A symbol read out after it adds nothing.
                        .accessibilityHidden(true)

                    Text("Set up OpenFactor")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Deliberately says nothing about iCloud. Sync is off by default, so the first
            // person to read this screen always has it off, and a paragraph about what iCloud
            // carries would be describing something that is not happening. What is true in both
            // configurations is the key and where it lives, so that is what this says. iCloud is
            // explained on the screen that has the switch, where the decision is being made.
            Section {
                Text(
                    """
                    Your accounts are encrypted with a key that never leaves this iPhone. \
                    Anything else that ends up holding them, a backup or another device, holds \
                    them encrypted.
                    """
                )
            }

            Section {
                // The same button as the empty list's "Add an account", from the same
                // definition rather than by hand. Both screens ask for one thing and nothing
                // else, so they get the one prominent control this app has.
                // Centred with spacers rather than `.frame(maxWidth: .infinity)`. A prominent
                // button style paints its background into whatever frame it is given, so that
                // modifier stretched the capsule instead of centring it.
                HStack {
                    Spacer()
                    Button { model.offerPassphrase() } label: {
                        PrimaryActionLabel("Create my vault")
                    }
                    .primaryActionStyle()
                    Spacer()
                }
                // Centres the button in the band between the explanation card and the footer
                // beneath it. The two paddings are different on purpose and are measured rather
                // than chosen from the spacing scale: the room above a row comes from section
                // spacing and the room below comes from footer spacing, and those are not the
                // same size, so equal padding would not produce equal gaps.
                .padding(.top, Tokens.Spacing.tight)
                .padding(.bottom, 12)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                // It used to say the passphrase was the only way to reach your accounts from a
                // new iPhone. That is false with sync off, where nothing reaches a new iPhone at
                // all. What the passphrase actually does is rebuild the key, and the case that
                // happens in most often is a restore, where the encrypted accounts come back
                // from a backup and the key deliberately does not.
                Text(
                    """
                    OpenFactor will show you a passphrase, once. It is what rebuilds this key if \
                    this iPhone ever loses it, after restoring from a backup for example.
                    """
                )
            }

            // The case this screen most needs to get right, and the one nothing in the state
            // can distinguish: a second device whose wrapped record has not arrived yet looks
            // exactly like a first device. This project measured iCloud Keychain taking close
            // to half an hour. Creating a second vault here would strand every account sealed
            // under the first, so the wait is described rather than left to be discovered.
            //
            // This is the one section that has to name iCloud, because arrival is the thing it
            // is about and arrival only happens with sync on. The condition is stated rather
            // than assumed: somebody whose other iPhone has sync off will wait forever, and
            // telling them to wait would be the same false promise in a politer form.
            //
            // Whether the record arrives does not depend on *this* iPhone's sync setting. The
            // record carries its own synchronizable attribute and the lookup accepts either, so
            // a phone with sync off still sees one that another phone synced.
            Section {
                Button("Check again") { model.refresh() }
            } header: {
                Text("Already using OpenFactor?")
            } footer: {
                Text(
                    """
                    If you already use OpenFactor on another iPhone or iPad with iCloud sync \
                    turned on, your accounts may still be on their way here. iCloud can take up \
                    to an hour. Wait, then check again: this screen will ask for your existing \
                    passphrase once they arrive.

                    Creating a vault now would leave those accounts unreadable.
                    """
                )
            }

            if let failure = model.failure {
                Section {
                    Text(failure).foregroundStyle(.red)
                }
            }
        }
        // The gaps above and below the explanation were the Form's default section spacing,
        // which is sized for a settings screen with many sections rather than a welcome screen
        // with three. Tightened once here rather than padded around per section.
        .listSectionSpacing(Tokens.Spacing.medium)
        // The space above the key was the scroll view's own top margin, not the navigation bar,
        // which on this screen has no title and collapses to nothing. Hiding the bar changed
        // the layout by zero points; this is where the room actually was.
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - The passphrase

    private func passphrase(_ generated: String) -> some View {
        Form {
            Section {
                grid(generated)

                // A tap that changes nothing on screen needs an answer. The account list
                // already solved this, with a haptic and a "Copied" confirmation, and these
                // screens simply did not use it. Reused rather than reinvented.
                Button {
                    CodeClipboard.copy(passphrase: BackupPassphrase.grouped(generated))
                    copies += 1
                    hasCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        hasCopied = false
                    }
                } label: {
                    Label(
                        hasCopied ? "Copied" : "Copy passphrase",
                        systemImage: hasCopied ? "checkmark" : "doc.on.doc")
                }
                .sensoryFeedback(trigger: copies) { _, _ in .success }

                // The same action the export screen offers, so it carries the same label and
                // sits in the same place: inside the passphrase section, under the copy button,
                // rather than down beside Continue. It used to go back to the intro screen,
                // which is not what any of these labels say.
                Button("Generate a different one") { model.offerPassphrase() }
                    .disabled(model.isWorking)
            } footer: {
                // Says what this is for, in the two situations it is actually for. The earlier
                // version explained how a vault passphrase differs from an archive's, which on
                // a first run describes a thing that does not exist yet and lands as noise.
                //
                // `docs/VAULT.md` still requires the two be distinguishable. That is satisfied
                // by the screen title, "Your vault passphrase", which is a label rather than a
                // paragraph. The comparison belongs on the export screen, where somebody is
                // holding a second string and the distinction is a live question.
                Text(
                    """
                    You need this if you delete and reinstall OpenFactor, or set it up on \
                    another iPhone signed in to the same Apple Account.
                    """
                )
            }

            Section {
                Toggle("I have saved this passphrase", isOn: $model.hasSavedPassphrase)
                    .disabled(model.isWorking)
            } footer: {
                // Two sentences doing two jobs. The first tells somebody to write it down,
                // against a lifetime of being told never to write secrets down. The second is
                // what earns that instruction: the passphrase is not a credential on its own.
                //
                // "Your Apple Account or this iPhone" rather than only the Apple Account. The
                // encrypted copy also sits on the device and in a device backup, so naming
                // iCloud alone would be the more comforting claim and the less true one.
                Text(
                    """
                    OpenFactor cannot show it again and keeps no copy, so write it down \
                    somewhere you will still have it. On its own it opens nothing: anyone using \
                    it would also need your Apple Account or this iPhone.
                    """
                )
            }

            Section {
                Button {
                    Task { await model.createVault() }
                } label: {
                    HStack {
                        Text("Continue")
                        if model.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!model.hasSavedPassphrase || model.isWorking)

                if let failure = model.failure {
                    Text(failure).foregroundStyle(.red)
                }
            } footer: {
                Text("Nothing has been created yet. Your vault is set up when you continue.")
            }
        }
    }

    /// The same shape the export screen uses, for the same reason: six groups of four, read
    /// left to right, so a transcription can be checked group by group.
    private func grid(_ generated: String) -> some View {
        let groups = BackupPassphrase.groups(generated)
        let rows = stride(from: 0, to: groups.count, by: 3).map {
            Array(groups[$0..<min($0 + 3, groups.count)])
        }

        return Grid(horizontalSpacing: 18, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, group in
                        Text(group)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vault passphrase")
        // Spelled out, because VoiceOver reads a run of letters as a word it invents and this
        // is a string that has to be transcribed exactly.
        .accessibilityValue(generated.map(String.init).joined(separator: " "))
    }
}
