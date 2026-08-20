import OpenFactorCore
import SwiftUI

@main
struct OpenFactorApp: App {

    /// The colour scheme override, applied at the root so every sheet inherits it.
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearancePreference.system.rawValue

    /// The one store the app uses. Constructed here and passed down, so there is exactly
    /// one place in the app that decides where secrets live.
    ///
    /// It is deliberately not an `InMemorySecretStore`. That type exists in the library
    /// for previews and tests, and if it ever appears in this file, that is the bug.
    ///
    /// No access group is named here on purpose. The entitlement declares exactly one, and
    /// the Keychain uses the first group in that list as the default for anything written
    /// without one. Naming it in code would mean hardcoding the team identifier, which does
    /// not belong in a public repository, and would give the group two homes that could
    /// disagree. The entitlement is the single place it is written down.
    private let store: SyncAwareKeychainStore

    /// The vault gate's state, which includes a generated passphrase when one is on screen.
    ///
    /// **Held here so App Lock cannot destroy it.** The lock screen replaces the root view, and
    /// anything owned below it goes with it. A generated passphrase lives only in this object,
    /// so owning it at the top is what lets somebody copy it, go and paste it somewhere, and
    /// come back to the same screen.
    @State private var gate: VaultGateModel

    /// The add flow's state: the sheet's presence, the pushed manual screen, and every typed
    /// field. Owned here so App Lock cannot destroy a half typed secret; leaving the app to copy
    /// the key out of an email or a password manager is how manual entry is actually used.
    @State private var addSession: AddAccountSession

    /// What arrived from outside: a file opened elsewhere, or an image the share extension left
    /// in the group container.
    ///
    /// **Owned here for the same reason the gate is.** Collecting is destructive, so a collection
    /// that happens moments before App Lock swaps the root would take the image out of the
    /// container and then be thrown away with the view that asked for it. Sharing would appear to
    /// do nothing at all, which is what it did.

    /// What has arrived and is waiting to be dealt with.
    ///
    /// **The newest arrival wins, and this is a decision rather than an accident.** Two reviews
    /// filed the older behaviour as a defect: a link opened while a shared image waited threw the
    /// image away with no sign. The answer built for that was a queue holding two, and it produced
    /// two findings of its own in the file no test can reach, plus an exception in a normative
    /// page that had always said an arrival takes precedence over whatever was open.
    ///
    /// Tested on hardware instead of argued about. What a person actually does is tap the newest
    /// thing, and a superseded arrival costs one repeated gesture rather than an account: a link
    /// can be tapped again and an image can be shared again. Against an app spamming links, last
    /// wins is also the better rule, because first wins lets whatever arrives first block a
    /// genuine share until it is dismissed, which is exactly the sequence that was reproduced.
    ///
    /// What makes it a rule rather than the behaviour that was observed: the superseded item is
    /// **swept**, not left in the inbox to reappear the one time in four that something else
    /// triggers a collection.
    @State private var arrival: IdentifiedArrival?

    init() {
        let keys = VaultKeyStore()
        let store = SyncAwareKeychainStore(vaultKeys: keys)
        self.store = store

        // **The wrapped key is created under the sync preference that is already set**, rather
        // than always locally with a conversion expected later. Round two of gate A4's scope 1
        // found the leftover: erase from the locked screen with sync on, create again, and the
        // wrap is written device-only while every new account syncs, which is the original
        // total-loss shape reached by a different tap. Nothing prompts anybody to toggle a switch
        // that already reads "on".
        let wrapped = WrappedKeyStore(
            synchronizable: UserDefaults.standard.bool(forKey: PreferenceKey.syncEnabled))
        self.wrapped = wrapped
        _gate = State(
            initialValue: VaultGateModel(
                vault: Vault(keys: keys, wrapped: wrapped), store: store))
        _addSession = State(initialValue: AddAccountSession(store: store))
    }

    /// Kept so the launch reconcile below can reach it. See `reconcileWrappedKeySync`.
    private let wrapped: WrappedKeyStore

    /// Tries once per cold start to bring an already-written wrapped key into iCloud, when the
    /// preference says it belongs there.
    ///
    /// **Two things this deliberately does not do, both of which the comment used to imply.** It
    /// does nothing when the preference is off, because the withdrawal direction cannot drift:
    /// the switch is only flipped after a successful conversion, so a failed withdrawal leaves it
    /// honestly reading "on". And it abandons a failure in silence, which a review rated a medium
    /// and is filed as such: a device that fails this at every launch stays in the loss shape with
    /// nothing on screen saying so, unlike the access-group migration below, which refuses to hide
    /// its failures.
    ///
    /// **A fix to a toggle governs the next toggle, not the state a device is already in.** A
    /// phone that enabled sync before the wrapped key followed the accounts is sitting in the
    /// exact loss shape: accounts in iCloud, the key that opens them on one device, and nothing
    /// prompting anybody to flip a switch that already reads "on". Round two of gate A4 named it
    /// and pointed at this commit's own precedent, `VaultKeyStore.load` repairing a key written
    /// under the old rules, on the reasoning that the device most needing the fix is the one
    /// already working.
    ///
    /// Idempotent, and quiet: `setSynchronizable` updates in place and returns whether there was
    /// anything to move, so a device already in the right state does nothing and a device with no
    /// vault does nothing.
    private static func reconcileWrappedKeySync(_ wrapped: WrappedKeyStore) {
        let shouldSync = UserDefaults.standard.bool(forKey: PreferenceKey.syncEnabled)
        guard shouldSync else { return }
        _ = try? wrapped.setSynchronizable(true)
    }

    /// The lock and the snapshot cover. See `PrivacyShield` for why they live in their
    /// own window rather than in this view tree.
    @State private var lock = AppLockController()

    /// Whether the screen is being recorded, mirrored, or shared. Owned here and injected, so
    /// no view has to know how it is detected. See `ScreenCaptureMonitor`.
    @State private var capture = ScreenCaptureMonitor()

    /// Answers a watch asking for the vault key. The only path by which that key leaves this
    /// device, and the only reason this app talks to the watch at all.
    @State private var watchKeys = WatchKeyProvider()

    /// Set when the access group migration could not finish. See the alert below.
    ///
    /// Held as a flag rather than the error: reading through the store's existential
    /// widens the typed throw, and the alert says the same thing whatever went wrong.
    @State private var migrationFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                // Two kinds of lock, and only the cold one lives here. A lock that began
                // at launch has no interface to preserve, so the lock screen IS the root:
                // whatever renders first is what the person sees first, which is why it
                // cannot arrive on top of anything. A lock on return is not this branch
                // at all: it is a window PrivacyShield raises above the interface, and
                // the whole view tree beneath survives untouched, sheets, navigation and
                // half typed text included. That split, and the sequences that prove it,
                // are docs/APP_LOCK.md; the decisions are AppLockPresentation, tested.
                if lock.presentsRootLock {
                    LockScreenView(controller: lock)
                } else {
                    // The vault gate, not the list. A device that has accounts and no key must
                    // ask for its passphrase before anything is drawn, and a device that has
                    // never had a vault must be offered one: the list cannot render either
                    // state honestly, because to it both look like a shelf of unreadable rows.
                    VaultGateView(model: gate, store: store) {
                        AccountListView(store: store, arrival: $arrival, addSession: addSession)
                        // Accounts saved before the shared access group was declared are
                        // still in the app's bundle group. The phone reads them either
                        // way, so nothing looks wrong here; the watch cannot see them at
                        // all. Idempotent and cheap once there is nothing left to move,
                        // so it runs at every launch rather than behind a flag that could
                        // itself be wrong.
                        //
                        // A failure used to be swallowed here, on the reasoning that
                        // nothing is lost by it. That reasoning was wrong in one direction
                        // that matters: an account left in the old group is invisible on
                        // this phone, which reads every group it can reach, and shows up
                        // only as a watch with fewer accounts than it should have and no
                        // error anywhere. That is the exact bug this migration exists to
                        // fix, so failing to migrate must not be silent. Gate A2, F20.
                        .task {
                            do {
                                try store.migrateToDefaultAccessGroup()
                                migrationFailed = false
                            } catch {
                                migrationFailed = true
                            }
                        }
                        .alert(
                            "Some accounts were not moved",
                            isPresented: $migrationFailed
                        ) {
                            Button("OK") { migrationFailed = false }
                        } message: {
                            Text(
                                """
                                They are safe and still on this phone, but they will not \
                                reach your Apple Watch. Reopening OpenFactor tries again.
                                """
                            )
                        }
                    }
                }
            }
            // Anything a previous run left behind, removed before the interface exists.
            // The export screen deletes its own file when it goes away, which covers every
            // way a screen goes away and not the one where the process does not: force quit
            // from the app switcher, or an out of memory kill, while the file is on screen.
            // For the plaintext vault that would be every secret in the clear, sitting in
            // the container with nothing ever revisiting it. Found by the security review.
            .task { Self.reconcileWrappedKeySync(wrapped) }
            // **Unconditional, unlike the collection path**, which does nothing until the
            // scene is active, the lock is open, the vault is open and no arrival is pending. An
            // image shared to a locked phone that was never unlocked again used to stay in a
            // shared container.
            //
            // **On every activation, not only at launch.** The first version ran once per
            // process, which a review took apart: launch ten seconds after a share, the item is
            // fresh so it survives, cancel Face ID, and the process stays resident with the item
            // held for as long as iOS keeps it alive. A threshold evaluated once is not a
            // deadline. This is the same call, made every time the app comes forward, and it is
            // cheap: a directory listing.
            .task { SharedInbox().sweepStale() }
            .task { ExportViewModel.discardOrphanedFiles() }
            .task { watchKeys.activate() }
            // Over whatever is on screen, because the watch may ask at any moment and the
            // answer is the same wherever the person happens to be in the app. It cannot
            // appear while locked: the lock screen is the root then, and this modifier is
            // attached above it deliberately so the question waits rather than being missed.
            .alert("Set up your Apple Watch?", isPresented: watchAsking) {
                Button("Not now", role: .cancel) { watchKeys.decline() }
                Button("Set up Apple Watch") { watchKeys.approve() }
            } message: {
                // One line. The system alert is translucent on iOS 26 and this one lands on the
                // account list, which is a wall of saturated color, so every word that is not
                // load bearing is working against being read at all.
                Text("Your Apple Watch is asking for the key to your accounts.")
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                lock.scenePhaseChanged(to: phase)
                PrivacyShield.apply(lock)
                SharedInbox().sweepStale()
                collectWhatArrived()
            }
            .onChange(of: lock.isLocked) {
                PrivacyShield.apply(lock)
                // Unlocking does not change the scene phase, so without this an image shared
                // while the app was locked would wait for the next time it came forward.
                collectWhatArrived()
            }
            // A dismissal is the person's decision to discard the draft; a lock never flips
            // this, because the binding lives above the lock. That one asymmetry is the whole
            // mechanism by which typed text survives a lock and not a swipe down.
            .onChange(of: addSession.isPresented) { _, presented in
                if !presented { addSession.reset() }
            }
            .onChange(of: gate.stage) { collectWhatArrived() }
            .onOpenURL { url in
                guard let value = InboxOpener.arrival(from: url) else { return }

                // **This supersedes whatever was pending, and takes it off the device.** An
                // uncollected share left in the inbox is the difference between a rule and the
                // behaviour a hardware test caught: it reappeared on one run in four, whenever
                // some unrelated scene or lock event happened to trigger a collection later.
                SharedInbox().sweep()
                arrival = IdentifiedArrival(value: value)
            }
            // The root swap and the shield hide land in the same transaction, so there is
            // no frame between them for the interface to show through.
            .preferredColorScheme(
                (AppearancePreference(rawValue: appearance) ?? .system).colorScheme
            )
            .environment(\.isScreenCaptured, capture.isCaptured)
            // Coming back is a moment the flag can have changed without a notification
            // arriving, for instance a mirroring session started while the app was away.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { capture.refresh() }
            }
        }
    }

    /// The alert's binding. **The setter deliberately does nothing.**
    ///
    /// It used to decline on dismissal, on the reasoning that a question about releasing a key
    /// must never resolve as yes by default. That was right in intent and wrong in mechanism:
    /// SwiftUI sets this binding to false as part of dismissing the alert, *before* the button's
    /// action runs, so pressing "Set up Apple Watch" declined first and then found nothing left
    /// to approve. It failed every single time, which is what a deterministic ordering bug looks
    /// like from the outside.
    ///
    /// The intent is preserved without the mechanism: both buttons answer explicitly, and an
    /// alert that somehow goes away without either leaves the question unanswered, so it comes
    /// back rather than resolving itself.
    private var watchAsking: Binding<Bool> {
        Binding(
            get: { watchKeys.isAsking && !lock.isLocked },
            set: { _ in })
    }

    /// Takes whatever the share extension left, once there is somewhere to show it.
    ///
    /// **All three conditions are load bearing.** Not while locked, because the account list does
    /// not exist then and the image would be consumed with nothing to receive it. Not before the
    /// vault is open, because an import sheet over a setup screen is nonsense. And not if
    /// something is already waiting, or a second look would discard the first.
    private func collectWhatArrived() {
        // Collection is not a fresh arrival: it is this app noticing something shared earlier.
        // So it waits for the screen rather than superseding what is on it, which is the other
        // half of the newest-wins rule.
        guard scenePhase == .active, !lock.isLocked, gate.stage == .open, arrival == nil
        else {
            return
        }
        guard let value = InboxOpener.collect() else { return }
        arrival = IdentifiedArrival(value: value)
    }

}
