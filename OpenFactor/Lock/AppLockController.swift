import LocalAuthentication
import SwiftUI

/// Owns the lock engine, listens to the scene, and runs the unlock prompt.
///
/// Deliberately thin. Every decision about whether to lock lives in ``AppLockEngine``,
/// which is pure and tested; this class feeds it real dates and real scene transitions and
/// carries the one thing the engine must not know about, `LocalAuthentication`.
///
/// The preference is read at the moment of each event rather than held, the same pattern
/// as `SyncAwareKeychainStore` and for the same reason: a cached copy of a setting is a
/// bug waiting for the moment the setting changes.
@Observable
@MainActor
final class AppLockController {

    private var engine: AppLockEngine
    private let defaults: UserDefaults

    /// Whether the unlock prompt has already been offered for the current locked spell,
    /// so returning from the Face ID overlay does not immediately re-raise it.
    private var hasPrompted = false

    /// Set when unlocking is impossible rather than merely not yet done: the person
    /// enabled the lock and later removed their device passcode. Failing open would make
    /// the lock decorative, so it fails closed and says why.
    private(set) var unlockImpossibleReason: String?

    var isLocked: Bool {
        engine.isLocked
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = AppLockEngine(enabled: defaults.bool(forKey: PreferenceKey.appLockEnabled))
    }

    func scenePhaseChanged(to phase: ScenePhase, at date: Date = Date()) {
        switch phase {
        case .background:
            engine.appDidBackground(at: date)
            hasPrompted = false

        case .active:
            engine.appWillForeground(
                at: date,
                enabled: defaults.bool(forKey: PreferenceKey.appLockEnabled),
                gracePeriod: TimeInterval(defaults.integer(forKey: PreferenceKey.appLockGraceSeconds))
            )

        case .inactive:
            break

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
    func requestUnlock() async {
        guard isLocked else { return }
        hasPrompted = true

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
                engine.unlock()
            }
        } catch {
            // Cancelled or failed. Locked is already the right state, and the lock screen
            // with its button is already the right interface.
        }
    }

    /// Whether the prompt should be raised without a tap, once per locked spell.
    var shouldAutoPrompt: Bool {
        isLocked && !hasPrompted
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
}
