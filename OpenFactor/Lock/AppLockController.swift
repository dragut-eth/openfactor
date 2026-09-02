import LocalAuthentication
import SwiftUI

/// Feeds real dates and real scene transitions to the lock's two value types, and runs
/// the unlock prompt.
///
/// Deliberately thin, and thinner than it was. Whether the app is locked is decided by
/// `AppLockEngine`; what that looks like, root lock, lock window, or snapshot cover, is
/// decided by `AppLockPresentation`, which owns the engine. Both are pure and tested
/// against the sequences in `docs/APP_LOCK.md`. This class carries the one thing they
/// must not know about, `LocalAuthentication`, and nothing else: the first attempt at PR
/// 15b put presentation decisions in glue like this, and all three of its defects lived
/// there.
///
/// The preference is read at the moment of each event rather than held, the same pattern
/// as `SyncAwareKeychainStore` and for the same reason: a cached copy of a setting is a
/// bug waiting for the moment the setting changes.
@Observable
@MainActor
final class AppLockController {

    private var presentation: AppLockPresentation
    private let defaults: UserDefaults

    /// Set when unlocking is impossible rather than merely not yet done: the person
    /// enabled the lock and later removed their device passcode. Failing open would make
    /// the lock decorative, so it fails closed and says why.
    private(set) var unlockImpossibleReason: String?

    var isLocked: Bool { presentation.isLocked }

    /// The lock screen as the root view. Cold locks only, where no interface exists to
    /// preserve. `OpenFactorApp` branches on this.
    var presentsRootLock: Bool { presentation.presentsRootLock }

    /// The lock screen in a window above the untouched interface. Warm locks only.
    /// `PrivacyShield.apply` reads this.
    var lockWindowVisible: Bool { presentation.lockWindowVisible }

    /// The blank surface the app switcher photographs. `PrivacyShield.apply` reads this.
    var coverVisible: Bool { presentation.coverVisible }

    /// Whether the prompt should be raised without a tap, once per locked spell.
    var shouldAutoPrompt: Bool { presentation.shouldAutoPrompt }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presentation = AppLockPresentation(
            lockEnabled: defaults.bool(forKey: PreferenceKey.appLockEnabled))
    }

    #if DEBUG
        /// Called by the trace after every event, so one line carries the decision inputs and
        /// the decisions together. The window state is supplied by `PrivacyShield`, which is
        /// the only thing that knows it.
        func debugTrace(_ event: String, coverWindow: String) {
            LockTrace.shared.record(
                event,
                phase: presentation.debugPhaseName,
                settling: presentation.debugSettling,
                locked: presentation.isLocked,
                cover: presentation.coverVisible,
                lockWindow: presentation.lockWindowVisible,
                coverWindow: coverWindow)
        }
    #endif

    /// The system says the app is resigning active. **This is the signal the cover hangs on**,
    /// and `scenePhase` is not.
    ///
    /// SwiftUI reports scene phase *changes*. A departure from a scene it already believes is
    /// inactive is not a change, so nothing is delivered. That state is reachable in ordinary
    /// use: the Face ID prompt drives the scene inactive, and the return to active is not
    /// always delivered afterwards. A trace taken on an iPhone 15 Pro on 2026-08-22 caught it:
    /// an unlock at t=42.139 with no `.active` for the next six seconds, then the person left
    /// and **the first event the app received was `.background`**, which is after the system has
    /// already photographed the screen. Two of three unlocks in that trace got their `.active`
    /// back and one did not, which is why the leak looked intermittent.
    ///
    /// `UIApplication.willResignActiveNotification` fires on every real resignation regardless
    /// of what SwiftUI believes, so it cannot be swallowed the same way.
    ///
    /// **Kept alongside `scenePhase` rather than replacing it.** Both funnel into the same
    /// idempotent state machine: `willResignActive` is a plain assignment, and a duplicate
    /// `didBecomeActive` cannot re-lock because the engine clears `backgroundedAt` in a `defer`
    /// and guards on it. Two independent signals for one event is the point, not an oversight.
    func systemWillResignActive() {
        presentation.willResignActive()
        #if DEBUG
            debugTrace("UIKit willResignActive", coverWindow: PrivacyShield.debugCoverState)
        #endif
    }

    /// The system says the app became active. Clears the Face ID settling flag even when
    /// SwiftUI never reports `.active`, which is the other half of the same defect: without
    /// this the flag stays armed and suppresses the next cover.
    func systemDidBecomeActive(at date: Date = Date()) {
        presentation.didBecomeActive(
            at: date,
            enabled: defaults.bool(forKey: PreferenceKey.appLockEnabled),
            gracePeriod: TimeInterval(defaults.integer(forKey: PreferenceKey.appLockGraceSeconds))
        )
        #if DEBUG
            debugTrace("UIKit didBecomeActive", coverWindow: PrivacyShield.debugCoverState)
        #endif
    }

    /// The system says the app entered the background. **The last signal before the photograph,
    /// and in one measured sequence the only one.**
    ///
    /// `willResignActive` cannot fire for an app that was never active. After a Face ID unlock
    /// the scene is sometimes left inactive and stays there while the person uses the app, so
    /// leaving produces no resignation at all: inactive straight to background. A trace on an
    /// iPhone 15 Pro on 2026-08-22 caught exactly that, with the unlock at t=12.106 and nothing
    /// until background at t=13.985.
    ///
    /// **The cover cannot be raised earlier in that case**, because during that window the app
    /// is inactive and showing a working interface the person is looking at. Covering it then
    /// would black out the app in their hands. So background is the earliest honest moment, and
    /// the UIKit notification reaches it before SwiftUI's `scenePhase` does.
    func systemDidEnterBackground(at date: Date = Date()) {
        presentation.didEnterBackground(at: date)
        #if DEBUG
            debugTrace("UIKit didEnterBackground", coverWindow: PrivacyShield.debugCoverState)
        #endif
    }

    func scenePhaseChanged(to phase: ScenePhase, at date: Date = Date()) {
        #if DEBUG
            let incoming =
                switch phase {
                case .background: "background"
                case .inactive: "inactive"
                case .active: "active"
                @unknown default: "unknown"
                }
            debugTrace("scenePhase->\(incoming) IN", coverWindow: PrivacyShield.debugCoverState)
        #endif
        defer {
            #if DEBUG
                debugTrace("scenePhase->\(incoming) OUT", coverWindow: PrivacyShield.debugCoverState)
            #endif
        }
        switch phase {
        case .background:
            presentation.didEnterBackground(at: date)

        case .inactive:
            // Both directions of `.inactive` arrive as the same value. The presentation
            // knows where the scene last stood, so it tells a resignation from a return
            // in transit; the distinction matters, because a resignation ends the cover
            // suppression and a transit must not.
            presentation.sceneBecameInactive()

        case .active:
            presentation.didBecomeActive(
                at: date,
                enabled: defaults.bool(forKey: PreferenceKey.appLockEnabled),
                gracePeriod: TimeInterval(
                    defaults.integer(forKey: PreferenceKey.appLockGraceSeconds))
            )

        @unknown default:
            break
        }
    }

    /// Runs the system authentication and unlocks on success.
    ///
    /// `.deviceOwnerAuthentication` is Face ID or Touch ID with the device passcode as
    /// fallback, which is the roadmap's requirement in one policy. Failure and
    /// cancellation both simply stay locked; there is no attempt counter here because the
    /// passcode fallback already has the system's.
    ///
    /// The prompt is marked as raised **before anything awaits.** Two auto-prompt paths
    /// exist, the root lock screen's `.task` and `PrivacyShield` showing the lock window,
    /// and both check `shouldAutoPrompt` on the main actor before calling this, so the
    /// synchronous mark is what guarantees one prompt rather than two.
    func requestUnlock() async {
        guard isLocked else { return }
        presentation.promptRaised()

        let context = LAContext()
        var unavailable: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &unavailable) else {
            // The one way to be locked with no way to authenticate: the passcode was
            // removed after the lock was enabled. Fail closed, and say what fixes it.
            unlockImpossibleReason = """
            App Lock needs your device passcode, which is no longer set. Set a passcode in \
            iOS Settings to unlock.
            """
            return
        }

        unlockImpossibleReason = nil

        do {
            if try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock your codes")
            ) {
                #if DEBUG
                    debugTrace("unlock OK IN", coverWindow: PrivacyShield.debugCoverState)
                #endif
                presentation.unlockSucceeded()
                #if DEBUG
                    debugTrace("unlock OK OUT", coverWindow: PrivacyShield.debugCoverState)
                #endif
            } else {
                presentation.unlockFailed()
            }
        } catch {
            // Cancelled or failed. Locked is already the right state, and the lock
            // surface with its button is already the right interface.
            presentation.unlockFailed()
        }
    }
}

/// Whether App Lock can work on this device at all.
///
/// Asked by the settings screen before allowing the toggle on. A device with no passcode
/// has nothing for `.deviceOwnerAuthentication` to verify, and offering a lock that cannot
/// lock would be the kind of false claim the settings screen's own header comment forbids.
enum AppLockAvailability {
    @MainActor
    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Asks the person to prove they are the owner, for an action that is not the lock.
    ///
    /// Erasing and exporting both need this whether or not App Lock is enabled: one
    /// destroys every secret, the other writes them all to a file, and neither should be
    /// two taps away on a phone someone handed over unlocked.
    ///
    /// **On a device with no passcode there is nothing to verify, and this returns true.**
    /// Refusing would deny someone a backup, or the ability to wipe a phone they are
    /// selling, on a device that is already wide open to anyone holding it. Decided with
    /// Xavier during PR 16 planning.
    ///
    /// **This used to end "The caller warns instead", and no caller warned.** Neither the
    /// export flow nor the erase screen branches on this, mentions it, or records that
    /// identity was skipped, so the sentence vouched for a mitigation that was never built
    /// and had done so since PR 16. Audit X2 found it as OF-A4. The claim is removed rather
    /// than the behaviour changed, because whether to warn on export, and whether the locked
    /// screen's "Start over" should require a passcode outright given that it erases every
    /// account from every device on the Apple Account, is an open decision recorded in
    /// `docs/audits/X/X2-fable-blind-audit.md`. `docs/MASVS.md` was accurate throughout: it
    /// downgrades MASVS-AUTH-3 to partial and never claimed a warning existed.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return true
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
