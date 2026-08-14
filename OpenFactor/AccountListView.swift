import Combine
import OpenFactorCore
import SwiftUI

/// The root screen: search, the list of cards, and the one timer that drives them all.
struct AccountListView: View {

    @State private var model: AccountListViewModel
    @State private var copied: UUID?
    @State private var isAdding = false
    @State private var isShowingSettings = false
    @State private var editMode: EditMode = .inactive

    @AppStorage(PreferenceKey.sortOrder) private var sortOrder = AccountSortOrder.manual.rawValue

    @State private var editing: AccountListViewModel.Row?
    @State private var recolouring: AccountListViewModel.Row?
    @State private var pendingDeletion: AccountListViewModel.Row?
    @State private var showingActions: AccountListViewModel.Row?

    private let store: any SecretStore

    /// The single timer for the whole screen. Ten accounts do not get ten timers.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(store: any SecretStore) {
        self.store = store
        _model = State(initialValue: AccountListViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("OpenFactor")
                // Inline, so the name sits in the bar rather than taking a row of the
                // screen away from the cards.
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $model.searchText, prompt: "Search accounts")
                .background(Tokens.Surface.background)
                .environment(\.editMode, $editMode)
                .onAppear {
                    model.sortOrder = AccountSortOrder(rawValue: sortOrder) ?? .manual
                    model.onSortOrderChange = { sortOrder = $0.rawValue }
                    model.load(at: Date())
                }
                .onChange(of: sortOrder) { _, raw in
                    model.sortOrder = AccountSortOrder(rawValue: raw) ?? .manual
                }
                .onReceive(tick) { model.tick(at: $0) }
                .toolbar { toolbar }
                .sheet(isPresented: $isAdding) {
                    AddAccountView(store: store) { model.load(at: Date()) }
                }
                .sheet(isPresented: $isShowingSettings) { SettingsView() }
                .sheet(item: $editing) { row in
                    EditAccountView(record: row.record) { issuer, name in
                        model.rename(row, issuer: issuer, name: name)
                    }
                }
                .confirmationDialog(
                    showingActions?.record.metadata.displayIssuer ?? "",
                    isPresented: Binding(
                        get: { showingActions != nil },
                        set: { if !$0 { showingActions = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: showingActions
                ) { row in
                    Button("Change colour") { recolouring = row }
                    Button("Edit details") { editing = row }
                    Button("Remove", role: .destructive) { pendingDeletion = row }
                }
                .sheet(item: $recolouring) { row in
                    AccountColorPicker(selected: row.record.metadata.color) { colour in
                        model.setColor(colour, for: row)
                    }
                }
                .alert(
                    "Remove \(pendingDeletion?.record.metadata.displayIssuer ?? "this account")?",
                    isPresented: Binding(
                        get: { pendingDeletion != nil },
                        set: { if !$0 { pendingDeletion = nil } }
                    ),
                    presenting: pendingDeletion
                ) { row in
                    Button("Remove", role: .destructive) {
                        model.delete(row)
                        pendingDeletion = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDeletion = nil }
                } message: { _ in
                    // The only irreversible thing in the app, so the consequence is named
                    // rather than left to be inferred from the word "remove".
                    Text(
                        """
                        Its secret is deleted from this device and cannot be recovered. \
                        If this is your only way to sign in, you will lose access to the account.
                        """
                    )
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }

        // Rearranging still makes no sense while a search hides part of the list. An
        // automatic sort is no longer a reason to hide this: dragging adopts the visible
        // order and switches to manual.
        if !model.rows.isEmpty && model.canReorder {
            ToolbarItem(placement: .topBarLeading) {
                // Not `EditButton`. That toggles whichever edit mode the toolbar happens
                // to see, which is not the one this view puts into the list's environment,
                // so the button would flip to Done while the rows stayed as they were.
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    Label(
                        editMode.isEditing ? "Done editing" : "Edit list",
                        systemImage: editMode.isEditing ? "checkmark" : "line.3.horizontal"
                    )
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                isAdding = true
            } label: {
                Label("Add account", systemImage: "plus")
            }
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
            ContentUnavailableView {
                Label("No accounts yet", systemImage: "lock.shield")
            } description: {
                Text("Scan the QR code a service shows you when you turn on two factor authentication.")
            } actions: {
                Button("Add an account") { isAdding = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.visibleRows.isEmpty && model.isSearching {
            ContentUnavailableView.search
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(model.visibleRows) { row in
                card(for: row).listRowStyling()
            }
            .onMove { model.move(from: $0, to: $1) }
            .onDelete { offsets in
                // Routed through the same confirmation as everything else. A swipe is a
                // convenient gesture, not a decision to lose an account.
                pendingDeletion = offsets.compactMap { model.visibleRows[$0] }.first
            }

            // Accounts this version cannot read. Shown rather than hidden: an account
            // that silently disappears is one the user thinks they have lost, and its
            // secret is still in the Keychain, intact.
            ForEach(model.unreadable, id: \.self) { id in
                UnreadableAccountRow(id: id).listRowStyling()
            }
        }
        .listStyle(.plain)
        .listRowSpacing(Tokens.Spacing.cardGap)
        .scrollContentBackground(.hidden)
    }

    private func card(for row: AccountListViewModel.Row) -> some View {
        AccountCard(model: row.card)
            .overlay(alignment: .topTrailing) { accessory(for: row) }
            .overlay {
                if copied == row.id {
                    CopiedBadge()
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            // Without this the drag preview is a rectangle, and the card's rounded corners
            // reveal its opaque backing as a dark notch. Naming the shape makes the lifted
            // card exactly the card.
            .contentShape(
                .dragPreview,
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
            )
            // Tap and long press are handled here rather than by a Button and a
            // `.contextMenu`. iOS appends its own entries to a system context menu, and on
            // this card it appended "Ask Siri", offering to hand the contents of a two
            // factor code card to an assistant that may process it off device. A
            // confirmation dialog shows only the buttons it is given, so the long press
            // survives without the additions. See SECURITY.md.
            .onTapGesture {
                guard !editMode.isEditing else { return }
                copy(row)
            }
            // `highPriorityGesture` rather than `onLongPressGesture` or
            // `simultaneousGesture`, both of which lose to the recognisers a List row
            // already carries and never fire.
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    guard !editMode.isEditing else { return }
                    showingActions = row
                }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(editMode.isEditing ? "" : "Copies the code")
            // VoiceOver cannot long press, so the same actions are offered as rotor
            // actions on the element itself.
            .accessibilityAction(named: "Change colour") { recolouring = row }
            .accessibilityAction(named: "Edit details") { editing = row }
            .accessibilityAction(named: "Remove") { pendingDeletion = row }
    }

    @ViewBuilder
    private func accessory(for row: AccountListViewModel.Row) -> some View {
        if editMode.isEditing {
            Menu {
                menu(for: row)
            } label: {
                CardButtonLabel(systemImage: "ellipsis")
            }
            .padding(Tokens.Spacing.large)
            .accessibilityLabel("Options for \(row.record.metadata.displayIssuer)")
        } else if !row.isTimeBased && copied != row.id {
            // Counter based accounts have no ring, because nothing counts down. What they
            // need instead is a way to ask for the next code.
            Button {
                model.advanceCounter(for: row)
            } label: {
                CardButtonLabel(systemImage: "arrow.trianglehead.clockwise")
            }
            .buttonStyle(.plain)
            .padding(Tokens.Spacing.large)
            .accessibilityLabel("Next code")
        }
    }

    @ViewBuilder
    private func menu(for row: AccountListViewModel.Row) -> some View {
        Button { recolouring = row } label: { Label("Change colour", systemImage: "paintpalette") }
        Button { editing = row } label: { Label("Edit details", systemImage: "pencil") }
        Button(role: .destructive) { pendingDeletion = row } label: {
            Label("Remove \(row.record.metadata.displayIssuer)", systemImage: "trash")
        }
    }

    private func copy(_ row: AccountListViewModel.Row) {
        guard model.copyCode(for: row, at: Date()) else { return }

        withAnimation(.snappy) { copied = row.id }

        Task {
            // 1.6 seconds was a guess, and it was consistently gone before it could be
            // observed. Long enough to notice, short enough not to sit on the card.
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.snappy) {
                if copied == row.id { copied = nil }
            }
        }
    }
}

// MARK: - Pieces

extension View {
    /// Cards provide their own background, so the list gets out of the way entirely.
    ///
    /// The margins live here rather than on the list. Padding the list itself moves its
    /// scroll indicator inward with it, so the indicator ends up drawn over the cards
    /// instead of beside them. Insetting the rows leaves the list full width, which is
    /// where the indicator belongs.
    ///
    /// Vertically the insets stay zero, because a row taller than the card it holds lifts
    /// that extra margin during a drag and shows the list's background as a dark band. The
    /// gap between cards belongs to `listRowSpacing`.
    fileprivate func listRowStyling() -> some View {
        listRowInsets(
            EdgeInsets(
                top: 0,
                leading: Tokens.Spacing.listInset,
                bottom: 0,
                trailing: Tokens.Spacing.listInset
            )
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// The round button that sits where the countdown ring would be.
private struct CardButtonLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Tokens.OnCard.primary)
            .frame(width: Tokens.Ring.size, height: Tokens.Ring.size)
            .background(Tokens.OnCard.primary.opacity(0.18), in: Circle())
    }
}

/// The confirmation after a tap.
///
/// Across the middle of the card rather than tucked into a corner, because the thing it
/// confirms is the whole reason the card was tapped and a person's eyes are already on
/// the digits. It deliberately does not repeat the code: the point of copying it is that
/// it no longer needs to be read off the screen.
private struct CopiedBadge: View {
    var body: some View {
        Label("Copied", systemImage: "checkmark")
            .font(.title3.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Tokens.OnCard.primary)
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.vertical, Tokens.Spacing.small + 2)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
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
