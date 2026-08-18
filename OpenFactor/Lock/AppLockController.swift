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

    func scenePhaseChanged(to phase: ScenePhase, at date: Date = Date()) {
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
                presentation.unlockSucceeded()
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
    /// selling, on a device that is already wide open to anyone holding it. The caller
    /// warns instead. Decided with Xavier during PR 16 planning.
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
