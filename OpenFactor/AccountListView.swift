import Combine
import OpenFactorCore
import SwiftUI

/// The root screen: search, the list of cards, and the one timer that drives them all.
struct AccountListView: View {

    @State private var model: AccountListViewModel
    @State private var copied: UUID?
    /// The add flow's state, owned by the app rather than this view so App Lock cannot destroy
    /// a half typed secret. `nil` only in previews. See `AddAccountSession`.
    private let addSession: AddAccountSession?

    @State private var fallbackAdding = false

    /// The presentation bit, from the session when there is one. The fallback exists so
    /// previews need not build a session to compile.
    private var isAdding: Binding<Bool> {
        guard let addSession else { return $fallbackAdding }
        return Binding(
            get: { addSession.isPresented },
            set: { addSession.isPresented = $0 })
    }
    @State private var isShowingSettings = false

    /// The one-time advice about locking, and the sheet it opens.
    ///
    /// **Fired when the first account lands, not at first launch.** With nothing stored the
    /// sentence is abstract, there are no codes to protect, and a dialog at that moment is
    /// dismissed without being read. See `docs/APP_LOCK.md`.
    @AppStorage(PreferenceKey.hasOfferedLockAdvice) private var hasOfferedLockAdvice = false
    @AppStorage(PreferenceKey.appLockEnabled) private var appLockEnabled = false
    @State private var offeringLockAdvice = false
    @State private var showingSystemLockSteps = false

    /// Whether the instructions have been read during this offer, which changes what the
    /// dialog's buttons say when it returns.
    ///
    /// **Offering "Show Me How" twice is the tell that nobody was listening.** Somebody who has
    /// just read the steps needs a way to say they are finished, not the same invitation again.
    @State private var hasReadLockSteps = false

    /// What arrived from outside the app, if anything.
    ///
    /// **Owned by the app, not by this view.** Collecting from the share extension's inbox is
    /// destructive: it takes the image out of the container. If this view held the result, a
    /// locked cold launch would rebuild this view and destroy it after the image was already
    /// gone, and sharing would silently do nothing. The same lesson as the vault passphrase, one
    /// screen along.
    @Binding var arrival: IdentifiedArrival?

    /// Whether the arrival sheet may present right now. False for exactly the gap between
    /// an arrival closing whatever was open and that sheet finishing its dismissal, because
    /// presenting one sheet while another animates out is a request SwiftUI drops on the
    /// floor: the arrival sheet would silently never appear, which is precisely what the
    /// share extension's flow cannot survive. Each closed sheet's `onDisappear` reopens
    /// this once the stage is actually clear.
    @State private var canPresentArrival = true

    /// The arrival, withheld while another sheet is still leaving. See `canPresentArrival`.
    private var presentedArrival: Binding<IdentifiedArrival?> {
        Binding(
            get: { canPresentArrival ? arrival : nil },
            set: { arrival = $0 })
    }

    /// Whether any sheet other than the arrival's is up. These are what an arrival closes.
    private var somethingElseIsPresented: Bool {
        isAdding.wrappedValue || isShowingSettings || editing != nil || recolouring != nil
            // **PR 15c's two, enrolled here rather than left outside it.** They were not, and an
            // arrival delivered at the same moment tore down both itself and the advice alert:
            // the dialog flashed and the shared image never presented at all. Measured on
            // hardware against checklist item 8.
            || offeringLockAdvice || showingSystemLockSteps
    }

    /// An arrival takes precedence: whatever was open closes, and the import presents
    /// clean from the root. The rule is Xavier's, verbatim in `docs/APP_LOCK.md`, and one
    /// consequence is deliberate: closing the add sheet is a dismissal, and a dismissal
    /// discards the draft. Somebody halfway through typing a secret who shares an image
    /// into the app has chosen the image.
    ///
    /// Nothing here waits or watches the lock. An arrival delivered while the app is
    /// locked runs this same closing under the lock window, and the sheet it presents is
    /// simply there after Face ID, never over the lock and never lost to it.
    private func arrivalChanged() {
        guard arrival != nil else {
            canPresentArrival = true
            return
        }

        guard somethingElseIsPresented else {
            canPresentArrival = true
            return
        }

        canPresentArrival = false
        isAdding.wrappedValue = false
        isShowingSettings = false
        editing = nil
        recolouring = nil
        pendingDeletion = nil
        // Advice yields to something the person actually did. **Only touched if it is actually
        // up**, because writing `false` over a binding that is already false is what churns
        // SwiftUI's presentation state. The common case is prevented at the trigger instead: it
        // is never offered while an arrival is pending.
        if offeringLockAdvice { offeringLockAdvice = false }
        if showingSystemLockSteps { showingSystemLockSteps = false }
    }

    /// The advice presentations, lifted out of `body`.
    ///
    /// **Not tidiness: the body stopped compiling.** An alert, a sheet and a change handler added
    /// to a chain already carrying six sheets and two alerts put it past what the Swift type
    /// checker will attempt, which fails with no error worth reading.
    private var lockAdvice: LockAdvice {
        LockAdvice(
            offering: $offeringLockAdvice,
            showingSteps: $showingSystemLockSteps,
            hasRead: $hasReadLockSteps,
            hasOffered: $hasOfferedLockAdvice,
            appLockEnabled: $appLockEnabled,
            arrivalIsPending: arrival != nil,
            somethingClosed: sheetDidClose)
    }

    /// A closed sheet has finished leaving. If an arrival was waiting on that, let it in.
    private func sheetDidClose() {
        if arrival != nil && !somethingElseIsPresented {
            canPresentArrival = true
        }
    }
    @State private var editMode: EditMode = .inactive

    @AppStorage(PreferenceKey.sortOrder) private var sortOrder = AccountSortOrder.manual.rawValue

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isScreenCaptured) private var isScreenCaptured

    @State private var editing: AccountListViewModel.Row?
    @State private var recolouring: AccountListViewModel.Row?
    @State private var pendingDeletion: AccountListViewModel.Row?

    /// Whether the account about to be deleted is in iCloud Keychain, read at the moment
    /// the alert is raised rather than inferred from the sync preference. The two can
    /// disagree, and this is the one dialog in the app where being wrong is permanent.
    @State private var pendingDeletionIsSynced = false

    private let store: any SecretStore

    /// The single timer for the whole screen. Ten accounts do not get ten timers.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        store: any SecretStore,
        arrival: Binding<IdentifiedArrival?> = .constant(nil),
        addSession: AddAccountSession? = nil,
        onCodeFailure: (() -> Void)? = nil
    ) {
        _arrival = arrival
        self.addSession = addSession
        self.store = store
        let model = AccountListViewModel(store: store)
        model.onCodeFailure = onCodeFailure
        _model = State(initialValue: model)
    }

    /// **Three properties rather than one chain, because one chain stopped compiling.**
    ///
    /// Twenty two modifiers on a single expression, five of them sheets with closures, put this
    /// past what the Swift type checker will attempt. **It built on the author's machine and
    /// failed on CI**, because the limit is a time budget rather than a fixed complexity, so a
    /// slower or differently versioned toolchain gives up where a fast one does not. "It compiles
    /// here" is not "it compiles".
    ///
    /// Each property below is its own type checking unit, which is the whole point of the split.
    var body: some View {
        NavigationStack {
            presentations
        }
    }

    /// The list itself, its chrome, and everything that reacts to a change.
    private var configured: some View {
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
                // A tap on a card produces no visible change except a badge that fades,
                // so the tap needs an answer you can feel. `sensoryFeedback` is the system
                // one, which means it honours the user's haptics setting rather than
                // buzzing regardless.
                .sensoryFeedback(trigger: copied) { _, current in
                    current == nil ? nil : .success
                }
                .toolbar { toolbar }
                .onChange(of: arrival?.id) { arrivalChanged() }
                // **Once, and only once there is something worth protecting.** `initial: true`
                // so a device that already has accounts and has never been asked still is:
                // the question is about what the app holds, not about when it was installed.
                .onChange(of: model.rows.isEmpty, initial: true) { _, isEmpty in
                    // **Never offered while something the person actually did is waiting.**
                    // An earlier version offered it anyway and let the arrival close it, which
                    // presents and tears down a dialog inside one update. On hardware that
                    // flashed the dialog, lost the import, and left SwiftUI's presentation state
                    // wedged so that Settings would not open afterwards. **Do not open it, rather
                    // than open it and close it.**
                    guard !isEmpty, !hasOfferedLockAdvice, arrival == nil else { return }
                    // **Asking is not showing, so the flag is not spent here.** It is spent when
                    // somebody answers, so an offer nobody saw is made again next launch.
                    offeringLockAdvice = true
                }
    }

    /// Everything that presents over the list.
    private var presentations: some View {
        configured
            .modifier(lockAdvice)
            .sheet(isPresented: isAdding) {
                if let addSession {
                    AddAccountView(session: addSession) { model.load(at: Date()) }
                        .onDisappear(perform: sheetDidClose)
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(store: store) { model.load(at: Date()) }
                    .onDisappear(perform: sheetDidClose)
            }
            // Three kinds of arrival, three destinations, and the distinctions matter.
            // An image and a code both hold a setup code and belong to the add flow, which
            // decodes one and reads the other; a file is an export or a backup and belongs
            // to the importer, which parses it. Nothing here is saved without a confirmation
            // screen, which is what makes an incoming URL safe to accept at all.
            .sheet(item: presentedArrival) { arrival in
                switch arrival.value {
                case let .image(data):
                    AddAccountView(store: store, image: data) { model.load(at: Date()) }
                case let .code(payload):
                    AddAccountView(store: store, code: payload) { model.load(at: Date()) }
                case let .file(url):
                    ImportView(store: store, arrival: .file(url)) {
                        model.load(at: Date())
                    }
                }
            }
            .sheet(item: $editing) { row in
                EditAccountView(record: row.record) { issuer, name, colour in
                    model.rename(row, issuer: issuer, name: name)
                    if colour != row.record.metadata.color {
                        model.setColor(colour, for: row)
                    }
                }
                .onDisappear(perform: sheetDidClose)
            }
            .sheet(item: $recolouring) { row in
                AccountColorPicker(selected: row.record.metadata.color) { colour in
                    model.setColor(colour, for: row)
                }
                .onDisappear(perform: sheetDidClose)
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
                //
                // The blast radius depends on whether the account is synced, and it
                // used to say "from this device" either way. Deleting a synchronizable
                // item removes it everywhere, so the person most likely to be misled
                // was the one keeping a second device precisely as their fallback.
                // Gate A2, F9.
                Text(
                    pendingDeletionIsSynced
                        ? """
                        Its secret is deleted from this device and from your other \
                        devices, and cannot be recovered. If this is your only way to \
                        sign in, you will lose access to the account.
                        """
                        : """
                        Its secret is deleted from this device and cannot be recovered. \
                        If this is your only way to sign in, you will lose access to the account.
                        """
                )
            }
    }

    /// Raises the delete confirmation, having first asked the Keychain where this
    /// account actually lives.
    ///
    /// A failure here is not worth blocking a deletion over, so it falls back to the
    /// wider warning. Overstating the consequence of an irreversible act is the safe
    /// direction to be wrong in.
    private func askToDelete(_ row: AccountListViewModel.Row) {
        if let store = store as? any SynchronizableSecretStore {
            pendingDeletionIsSynced = (try? store.syncState())?.synced.contains(row.id) ?? true
        } else {
            pendingDeletionIsSynced = false
        }

        pendingDeletion = row
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
                isAdding.wrappedValue = true
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
                // See `PrimaryAction`, which now owns these proportions and the reasoning
                // behind them, so this button and the vault setup's cannot drift apart.
                Button { isAdding.wrappedValue = true } label: {
                    PrimaryActionLabel("Add an account")
                }
                .primaryActionStyle()
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
                if let row = offsets.compactMap({ model.visibleRows[$0] }).first {
                    askToDelete(row)
                }
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
        Button {
            if editMode.isEditing {
                editing = row
            } else {
                copy(row)
            }
        } label: {
            // Masked while the screen is shared. The card stays, so a legitimately mirrored
            // app still reads as itself; only the digits go. See `ScreenCaptureMonitor`.
            AccountCard(model: row.card.maskedIfCaptured(isScreenCaptured))
        }
        .buttonStyle(.plain)
        // Follows the ring, which moves to the bottom of the card at accessibility sizes.
        .overlay(
            alignment: dynamicTypeSize.isAccessibilitySize ? .bottomTrailing : .topTrailing
        ) {
            accessory(for: row)
        }
        .overlay {
            if copied == row.id {
                CopiedBadge()
            }
        }
        // Both lifts, or neither. Without a named shape the system lifts the whole row,
        // which is full width and square cornered: the drag preview shows a dark notch at
        // each corner, and the context menu shows a bright margin down each side where the
        // row's own background sits either side of the inset card. Naming the shape makes
        // the lifted thing exactly the card in both cases.
        .contentShape(
            [.dragPreview, .contextMenuPreview],
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
        )
        // A system context menu, for the lift and the card preview behind it, which an
        // action sheet cannot reproduce. The cost is that iOS may append entries of its
        // own, including "Ask Siri". Accepted deliberately, see SECURITY.md.
        .contextMenu {
            menu(for: row)
        } preview: {
            // The same card, without the code. iOS may hand this preview to system
            // features we do not control, and "Ask Siri" is documented in SECURITY.md as
            // an accepted risk. Accepting the menu is not the same as feeding a live
            // second factor into it, and a preview showing the account is enough to know
            // which card was lifted.
            AccountCard(model: row.card.withoutCode)
                .frame(width: 320)
        }
        .accessibilityHint(editMode.isEditing ? "Opens details" : "Copies the code")
    }

    /// Nothing sits on a card while editing.
    ///
    /// There used to be an ellipsis menu here, covering a gap: in edit mode a long press is
    /// a drag, so the context menu is unreachable and its actions had nowhere else to live.
    /// The gap is now filled the way iOS fills it, by making a tap on the row open its
    /// details, which is what Reminders and Contacts do. That leaves edit mode as the three
    /// things an iOS user already expects, a delete control, a drag handle, and a row that
    /// opens when tapped, and it removes a control rather than restyling one.
    ///
    /// It also stopped the ring appearing to mutate into a button, since the ellipsis sat
    /// in exactly the ring's place.
    @ViewBuilder
    private func accessory(for row: AccountListViewModel.Row) -> some View {
        if editMode.isEditing {
            EmptyView()
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
        Button { recolouring = row } label: { Label("Change color", systemImage: "paintpalette") }
        Button { editing = row } label: { Label("Edit details", systemImage: "pencil") }
        Button(role: .destructive) { askToDelete(row) } label: {
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

    /// Scaled on the same curve as the card's ring, which is what it stands in for. The two
    /// are the same control in different clothes: the place a card tells you about its code.
    @ScaledMetric(relativeTo: .body) private var size = Tokens.Ring.size

    var body: some View {
        Image(systemName: systemImage)
            // Bold rather than semibold, and a little larger, because the ring beside it is
            // a 4.5 point stroke and a hairline glyph inside a disc of the same size reads
            // as the lighter, lesser control. This takes the glyph's own stroke from 1.75
            // points to 2.25.
            .font(.system(size: size * 0.56, weight: .bold))
            .foregroundStyle(Tokens.OnCard.primary)
            // Raised, because centred and looking centred are different things here.
            //
            // Reported as "it doesn't feel centred", and it was worth measuring rather than
            // nudging until it looked right: rendering the symbol offscreen and taking its
            // bounding box put it dead centre, within a tenth of a point. The alpha
            // weighted centroid is what disagrees. This glyph is a ring broken by a gap at
            // the top with an arrowhead on one end, and the gap removes more ink than the
            // arrowhead adds, so its mass sits 0.83 points below the middle of its box at
            // this size. An eye centres on mass, not on bounds. The fraction below is that
            // measurement, so it holds as the whole control scales.
            .offset(y: -size * 0.028)
            // The layout frame is the ring's frame, so the two sit on the same centre.
            .frame(width: size, height: size)
            // The disc is drawn larger, and the difference is the whole reason this looked
            // like the smaller control. A stroked `Circle` straddles its path, so the ring
            // reaches half a line width past the frame on every side and measures
            // `size + lineWidth` across. Matching the frame matched the wrong number. A
            // background view is centred on the frame and free to overflow it, so this
            // grows the visible disc to the ring's outer edge without moving anything.
            .background {
                Circle()
                    .fill(Tokens.OnCard.primary.opacity(0.18))
                    .frame(
                        width: size + Tokens.Ring.lineWidth,
                        height: size + Tokens.Ring.lineWidth
                    )
            }
    }
}

/// The confirmation after a tap.
///
/// Across the middle of the card rather than tucked into a corner, because the thing it
/// confirms is the whole reason the card was tapped and a person's eyes are already on
/// the digits. It deliberately does not repeat the code: the point of copying it is that
/// it no longer needs to be read off the screen.
private struct CopiedBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label("Copied", systemImage: "checkmark")
            .font(.title3.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Tokens.OnCard.primary)
            .padding(.horizontal, Tokens.Spacing.large)
            .padding(.vertical, Tokens.Spacing.small + 2)
            .background(.ultraThinMaterial, in: Capsule())
            // Reduce Motion means no scaling. A fade still reads as an appearance, and the
            // setting exists because movement makes some people ill, not because they
            // dislike it.
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
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
                Text("An account this version cannot read")
                    .font(Tokens.Text.issuer)

                // **Two causes now, and the old wording only covered one.** Before the vault
                // this could only mean a newer version had written the record, so the row
                // promised that updating would show it again. An account saved before the
                // vault existed reads the same way and updating does nothing for it, so the
                // promise would have been false for exactly the people who had one.
                //
                // The app does not claim to know which it is. Both sentences are true, the
                // likelier cause is first, and neither says the account is lost: the secret is
                // still in the Keychain either way.
                Text(
                    """
                    Its details are in a format this version does not understand, and its \
                    secret is untouched. Usually a newer version of OpenFactor wrote it, and \
                    updating will show it again. If it was saved before this device's vault, \
                    export it from a device that still shows it, or remove it with Erase all \
                    accounts.
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

/// The "Protect your codes" dialog, its instructions sheet, and the wiring that keeps both out of
/// an arrival's way.
///
/// **A modifier rather than lines in `body`**, because the body stopped type checking with them
/// inline. See `docs/APP_LOCK.md` for what each string says and why.
private struct LockAdvice: ViewModifier {
    @Binding var offering: Bool
    @Binding var showingSteps: Bool
    @Binding var hasRead: Bool
    @Binding var hasOffered: Bool
    @Binding var appLockEnabled: Bool

    /// Whether something the person actually did is waiting for the screen.
    let arrivalIsPending: Bool

    /// Reports that one of these has finished leaving, so an arrival held behind it can present.
    let somethingClosed: () -> Void

    func body(content: Content) -> some View {
        content
            // **An alert has no `onDisappear`, so its closing is reported here.** Without this an
            // arrival closes the advice, nothing tells `canPresentArrival` that the way is clear,
            // and the import never presents at all: a worse bug than the one being fixed, and the
            // reason this is wired rather than assumed.
            .onChange(of: offering) { _, showing in
                if !showing { somethingClosed() }
            }
            .alert("Protect your codes", isPresented: $offering) {
                if hasRead {
                    // Closes, and records nothing. An acknowledgement rather than a claim: the
                    // app cannot tell whether the iOS lock was turned on. It replaces "Not Now"
                    // rather than joining it, because two buttons doing the same thing in
                    // different words are two buttons.
                    Button("I Did It", role: .cancel) { hasOffered = true }
                } else {
                    Button("Show Me How") { showingSteps = true }
                }
                // **Only offered where it can be honoured.** Two ways it cannot be. A device
                // with no passcode cannot authenticate, and the settings toggle already refuses
                // there. And a lock that is already on cannot be turned on: the button wrote a
                // value that was already true and closed, which is a button that does nothing.
                //
                // The spec stated this rule and applied it to the first case only. Found on
                // hardware 2026-08-22 by switching the lock on and then adding an account.
                if AppLockAvailability.canAuthenticate, !appLockEnabled {
                    Button("Turn On App Lock") {
                        appLockEnabled = true
                        hasOffered = true
                    }
                }
                if !hasRead {
                    Button("Not Now", role: .cancel) { hasOffered = true }
                }
            } message: {
                // **The dialog still appears when App Lock is on, and that is deliberate.**
                // What it actually advocates is the iOS system lock, which gate E14 measured as
                // strictly stronger: it removes the app switcher exposure completely, from the
                // first frame, because the system draws it rather than the app. Somebody who has
                // already switched App Lock on is exactly who benefits from hearing that.
                //
                // What changes is the last sentence, which offers App Lock as an alternative and
                // reads as nonsense to somebody already using it.
                Text(
                    appLockEnabled
                        ? "Your accounts are encrypted, but anyone using your unlocked phone "
                            + "can see your codes.\n\nApp Lock is on. For stronger protection "
                            + "still, iOS can lock OpenFactor before it opens."
                        : "Your accounts are encrypted, but anyone using your unlocked phone "
                            + "can see your codes.\n\nFor stronger protection, iOS can lock "
                            + "OpenFactor before it opens. Or you can use App Lock.")
            }
            // **The choice comes back when the instructions close.** Every alert button dismisses
            // its alert, so "Show Me How" ends the dialog, and without this somebody who asked for
            // help landed on the list unable to tell whether anything had been switched on.
            .sheet(isPresented: $showingSteps) {
                hasRead = true
                // **Not over an arrival.** If these were closed because something was shared,
                // bringing the question straight back would put it in front of the import all
                // over again. Advice yields, and returns next launch.
                if !arrivalIsPending { offering = true }
                somethingClosed()
            } content: {
                SystemLockAdvice()
            }
    }
}
